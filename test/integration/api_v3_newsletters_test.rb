require "test_helper"

class ApiV3NewslettersTest < ActionDispatch::IntegrationTest
  setup do
    host! "api.example.com"
    @user = users(:new)
    @user.setting_on!(:api_v3)
    @address = authentication_tokens(:new_newsletter)
    @address.update!(description: "Tech", newsletter_tag: "Apple", created_at: 2.days.ago)
    application = @user.oauth_applications.create!(name: "Reader", redirect_uri: "")
    @token = application.access_tokens.create!(resource_owner_id: @user.id, scopes: "read write")
  end

  test "lists every address, active and inactive, oldest first, with an etag" do
    inactive = @user.authentication_tokens.newsletters.create!(token: "old.123", active: false, created_at: 3.days.ago)
    users(:ben).authentication_tokens.newsletters.create!(token: "theirs.123")

    get "/v3/newsletters/addresses", headers: bearer

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [inactive.id, @address.id], body["data"].map { it["id"] }
    assert_equal({
      "object" => "newsletter_address", "id" => @address.id, "address" => "token_new@newsletters.com", "token" => "token_new",
      "description" => "Tech", "default_tag" => "Apple", "active" => true, "created_at" => @address.created_at.utc.iso8601
    }, body["data"].last)
    assert_equal [nil, nil, false], body["data"].first.values_at("description", "default_tag", "active")

    get "/v3/newsletters/addresses", headers: bearer.merge("If-None-Match" => response.headers["ETag"])
    assert_response :not_modified
  end

  test "proposes an address for a cleaned prefix and creates it" do
    post "/v3/newsletters/addresses/new", params: {prefix: " My News!"}.to_json, headers: json

    assert_response :success
    proposal = JSON.parse(response.body)
    assert_equal "newsletter_address_proposal", proposal["object"]
    assert_match(/\Amynews\.\d{3}\z/, proposal["token"])
    assert_equal "#{proposal["token"]}@newsletters.com", proposal["address"]
    refute AuthenticationToken.exists?(token: proposal["token"])

    post "/v3/newsletters/addresses", params: {verified_token: proposal["verified_token"], description: "News", default_tag: nil}.to_json, headers: json

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal [proposal["token"], "News", nil, true], body.values_at("token", "description", "default_tag", "active")
    assert_equal @user.id, AuthenticationToken.find(body["id"]).user_id
  end

  test "a prefix with nothing left after cleaning is invalid" do
    post "/v3/newsletters/addresses/new", params: {prefix: "!!!"}.to_json, headers: json
    assert_problem "validation_failed", pointer: "/prefix"

    post "/v3/newsletters/addresses/new", params: {}.to_json, headers: json
    assert_problem "validation_failed", pointer: "/prefix"
  end

  test "a prefix with no free address is unavailable" do
    AuthenticationToken.stub(:generate_custom_token, nil) do
      post "/v3/newsletters/addresses/new", params: {prefix: "full"}.to_json, headers: json
    end
    assert_problem "prefix_unavailable"
  end

  test "a tampered or missing verified token is invalid" do
    signed = AuthenticationToken.address_verifier.generate("mine.123")
    post "/v3/newsletters/addresses", params: {verified_token: "#{signed}x"}.to_json, headers: json
    assert_problem "validation_failed", pointer: "/verified_token"

    post "/v3/newsletters/addresses", params: {verified_token: nil}.to_json, headers: json
    assert_problem "validation_failed", pointer: "/verified_token"
    refute AuthenticationToken.exists?(token: "mine.123")
  end

  test "a proposal taken before it is created is unavailable" do
    signed = AuthenticationToken.address_verifier.generate("taken.123")
    users(:ben).authentication_tokens.newsletters.create!(token: "taken.123")

    post "/v3/newsletters/addresses", params: {verified_token: signed}.to_json, headers: json

    assert_problem "prefix_unavailable"
  end

  test "creates a random address without a verified token" do
    assert_difference -> { @user.authentication_tokens.newsletters.count } do
      post "/v3/newsletters/addresses", params: {default_tag: "News"}.to_json, headers: json
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_match(/\A[a-z]{5}\z/, body["token"])
    assert_equal [nil, "News"], body.values_at("description", "default_tag")
  end

  test "updates, deactivates and reactivates an address" do
    patch "/v3/newsletters/addresses/#{@address.id}", params: {description: nil, default_tag: "Swift", active: false}.to_json, headers: json

    assert_response :success
    assert_equal [nil, "Swift", false], JSON.parse(response.body).values_at("description", "default_tag", "active")
    refute @address.reload.active

    patch "/v3/newsletters/addresses/#{@address.id}", params: {active: true}.to_json, headers: json
    assert_response :success
    assert_equal [nil, "Swift", true], JSON.parse(response.body).values_at("description", "default_tag", "active")

    patch "/v3/newsletters/addresses/#{@address.id}", params: {active: "no"}.to_json, headers: json
    assert_problem "validation_failed", pointer: "/active"
  end

  test "another user's address is not found" do
    patch "/v3/newsletters/addresses/#{authentication_tokens(:ben_newsletter).id}", params: {active: false}.to_json, headers: json
    assert_response :not_found
    assert authentication_tokens(:ben_newsletter).reload.active

    patch "/v3/newsletters/addresses/#{@user.authentication_tokens.cookies.create!.id}", params: {active: false}.to_json, headers: json
    assert_response :not_found
  end

  test "lists the senders of every address by name, with whether each is subscribed" do
    inactive = @user.authentication_tokens.newsletters.create!(token: "old.123", active: false)
    allowed = sender!("platformer", token: @address.token)
    blocked = sender!("Joel", token: inactive.token)
    @user.subscriptions.create!(feed: allowed.feed)
    sender!("Theirs", token: authentication_tokens(:ben_newsletter).token)

    get "/v3/newsletters/senders", headers: bearer

    assert_response :success
    data = JSON.parse(response.body)["data"]
    assert_equal [blocked.id, allowed.id], data.map { it["id"] }
    assert_equal({"object" => "newsletter_sender", "id" => blocked.id, "name" => "Joel", "email" => "joel@example.com",
                  "address_id" => inactive.id, "feed_id" => blocked.feed_id, "subscribed" => false}, data.first)
    assert_equal [@address.id, true], data.last.values_at("address_id", "subscribed")

    get "/v3/newsletters/senders", headers: bearer.merge("If-None-Match" => response.headers["ETag"])
    assert_response :not_modified
  end

  test "allows and blocks a sender by subscribing to its feed" do
    sender = sender!("Joel", token: @address.token)

    patch "/v3/newsletters/senders/#{sender.id}", params: {subscribed: true}.to_json, headers: json
    assert_response :success
    assert JSON.parse(response.body)["subscribed"]
    assert @user.subscriptions.exists?(feed_id: sender.feed_id)

    patch "/v3/newsletters/senders/#{sender.id}", params: {subscribed: false}.to_json, headers: json
    assert_response :success
    refute JSON.parse(response.body)["subscribed"]
    refute @user.subscriptions.exists?(feed_id: sender.feed_id)

    patch "/v3/newsletters/senders/#{sender.id}", params: {}.to_json, headers: json
    assert_problem "validation_failed", pointer: "/subscribed"
  end

  test "another user's sender is not found" do
    sender = sender!("Theirs", token: authentication_tokens(:ben_newsletter).token)
    patch "/v3/newsletters/senders/#{sender.id}", params: {subscribed: true}.to_json, headers: json
    assert_response :not_found
    refute @user.subscriptions.exists?(feed_id: sender.feed_id)
  end

  private

  def sender!(name, token:)
    feed = Feed.create!(feed_url: "https://example.com/#{name.downcase}", title: name, feed_type: :newsletter)
    NewsletterSender.create!(feed: feed, token: token, full_token: token, email: "#{name.downcase}@example.com", name: name)
  end

  def assert_problem(code, pointer: nil)
    assert_response :unprocessable_content
    body = JSON.parse(response.body)
    assert_equal code, body["code"]
    assert_equal pointer, body["errors"].first["pointer"] if pointer
  end

  def bearer
    {"Authorization" => "Bearer #{@token.plaintext_token}"}
  end

  def json
    bearer.merge("Content-Type" => "application/json")
  end
end
