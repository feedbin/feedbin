require "test_helper"

class ApiV3ShareServicesTest < ActionDispatch::IntegrationTest
  setup do
    host! "api.example.com"
    @user = users(:new)
    @user.setting_on!(:api_v3)
    @feed = Feed.create!(feed_url: "https://example.com/feed", host: "example.com", title: "Example")
    @user.subscriptions.create!(feed: @feed)
    @entry = @feed.entries.create!(title: "A Post", content: "<p>Hi</p>", url: "https://example.com/post", public_id: SecureRandom.hex, entry_id: SecureRandom.hex)
    application = @user.oauth_applications.create!(name: "Reader", redirect_uri: "feedbin-test://oauth")
    @token = application.access_tokens.create!(resource_owner_id: @user.id, scopes: "read write account")
  end

  test "lists every offered service with how it is set up and shares" do
    get "/v3/share_services", headers: bearer
    assert_response :success
    services = JSON.parse(response.body)["data"].index_by { it["id"] }
    refute services.key?("pocket")
    assert_equal %w[object id label setup sharing status share_url settings choices default_choice], services["email"].keys
    assert_equal [["email", "form", "inactive"], ["token", "form", "inactive"], ["oauth", "send", "inactive"], ["server", "form", "inactive"], ["none", "link", "inactive"], ["kindle", "send", "inactive"]],
      %w[email pinboard instapaper mastodon twitter kindle].map { services[it].values_at("setup", "sharing", "status") }
    assert_equal "https://twitter.com/intent/tweet?url=${url}&text=${title}", services["twitter"]["share_url"]
  end

  test "turns services on with their settings, and off" do
    put "/v3/share_services/email", params: {email_name: "Ben", email_address: "ben@example.com"}.to_json, headers: json
    assert_response :success
    assert_equal ["active", {"email_name" => "Ben", "email_address" => "ben@example.com", "kindle_address" => nil, "mastodon_host" => nil}], JSON.parse(response.body).values_at("status", "settings")

    put "/v3/share_services/kindle", params: {}.to_json, headers: json
    assert_response :unprocessable_content
    assert_equal "/kindle_address", JSON.parse(response.body)["errors"].first["pointer"]

    put "/v3/share_services/twitter", params: {}.to_json, headers: json
    assert_equal "active", JSON.parse(response.body)["status"]

    put "/v3/share_services/instapaper", params: {}.to_json, headers: json
    assert_response :unprocessable_content
    assert_equal "authorization_required", JSON.parse(response.body)["errors"].first["code"]

    delete "/v3/share_services/email", headers: bearer
    assert_response :no_content
    refute @user.supported_sharing_services.exists?(service_id: "email")
  end

  test "a token is checked with the service" do
    Share::Pinboard.stub_any_instance(:request_token, ->(_user, token) { (token == "good") ? OpenStruct.new(token: token, secret: "n/a") : raise(OAuth::Unauthorized.new(OpenStruct.new(code: 401, message: "no"))) }) do
      put "/v3/share_services/pinboard", params: {token: "bad"}.to_json, headers: json
      assert_response :unprocessable_content
      assert_equal "token_invalid", JSON.parse(response.body)["code"]

      put "/v3/share_services/pinboard", params: {token: "good"}.to_json, headers: json
      assert_response :success
      assert_equal "good", @user.supported_sharing_services.find_by!(service_id: "pinboard").access_token
    end
  end

  test "signs in through the browser and comes back to the app" do
    post "/v3/share_services/instapaper/authorization", params: {return_to: "https://evil.example/"}.to_json, headers: json
    assert_response :unprocessable_content
    assert_equal "/return_to", JSON.parse(response.body)["errors"].first["pointer"]

    url = start_instapaper_authorization
    state = Rack::Utils.parse_query(url.query)["state"]
    assert url.to_s.start_with?("https://www.instapaper.com/oauth2/authorize")
    # the service can't read who the state is for, or where it goes back to
    readable = state.split("--").map { Base64.urlsafe_decode64(it) }.join
    refute_match "feedbin-test", readable
    refute_match "user_id", readable

    host! "example.com"
    Share::Instapaper.stub_any_instance(:request_access, ->(_params) { {access_token: "abc"} }) do
      get "/supported_sharing_services/instapaper/oauth2_response", params: {code: "c0de", state: state}
    end
    assert_redirected_to "feedbin-test://share-services?service_id=instapaper&status=active"
    assert_equal "abc", @user.supported_sharing_services.find_by!(service_id: "instapaper").access_token

    # a state signs in once
    Share::Instapaper.stub_any_instance(:request_access, ->(_params) { {access_token: "replayed"} }) do
      get "/supported_sharing_services/instapaper/oauth2_response", params: {code: "c0de", state: state}
    end
    assert_redirected_to "feedbin-test://share-services?service_id=instapaper&status=failed"
    assert_equal "abc", @user.supported_sharing_services.find_by!(service_id: "instapaper").access_token

    host! "api.example.com"
    state = Rack::Utils.parse_query(start_instapaper_authorization.query)["state"]
    host! "example.com"
    get "/supported_sharing_services/instapaper/oauth2_response", params: {state: state}
    assert_redirected_to "feedbin-test://share-services?service_id=instapaper&status=declined"

    get "/supported_sharing_services/instapaper/oauth2_response", params: {code: "c0de", state: "forged"}
    assert_response :redirect
    refute_match "feedbin-test://", response.location
  end

  test "signs in to an OAuth 1 service through the browser, once" do
    request_token = OpenStruct.new(token: "req", secret: "s3cret", authorize_url: "https://www.tumblr.com/oauth/authorize?oauth_token=req")
    Share::Tumblr.stub_any_instance(:request_token, request_token) do
      post "/v3/share_services/tumblr/authorization", params: {return_to: "feedbin-test://share-services"}.to_json, headers: json
    end
    assert_response :created
    assert_equal request_token.authorize_url, JSON.parse(response.body)["authorize_url"]

    host! "example.com"
    access = ->(token, secret, verifier) { (token == "req" && secret == "s3cret" && verifier == "v") ? OpenStruct.new(token: "acc", secret: "acc-s") : raise("wrong") }
    Share::Tumblr.stub_any_instance(:request_access, access) do
      SupportedSharingService.stub_any_instance(:after_activate, nil) do
        get "/supported_sharing_services/tumblr/oauth_response", params: {oauth_token: "req", oauth_verifier: "v"}
      end
    end
    assert_redirected_to "feedbin-test://share-services?service_id=tumblr&status=active"
    assert_equal "acc", @user.supported_sharing_services.find_by!(service_id: "tumblr").access_token

    # the request token is gone, so the callback can't be replayed into the app
    get "/supported_sharing_services/tumblr/oauth_response", params: {oauth_token: "req", oauth_verifier: "v"}
    refute_match "feedbin-test://", response.location.to_s
  end

  test "shares an article to a service set up for it" do
    post "/v3/share_services/email/shares", params: {entry_id: @entry.id, to: "a@example.com"}.to_json, headers: json
    assert_response :unprocessable_content
    assert_equal "needs_setup", JSON.parse(response.body)["code"]

    @user.supported_sharing_services.create!(service_id: "email")
    Sidekiq::Testing.fake! do
      post "/v3/share_services/email/shares", params: {entry_id: @entry.id, to: "a@example.com", subject: "Look", body: "", readability: false}.to_json, headers: json
    end
    assert_response :created
    assert_equal({"object" => "share", "service_id" => "email", "entry_id" => @entry.id}, JSON.parse(response.body))

    post "/v3/share_services/email/shares", params: {entry_id: 0, to: "a@example.com"}.to_json, headers: json
    assert_response :not_found

    @user.supported_sharing_services.create!(service_id: "twitter")
    post "/v3/share_services/twitter/shares", params: {entry_id: @entry.id}.to_json, headers: json
    assert_response :unprocessable_content
  end

  test "keeps the user's own share links" do
    post "/v3/custom_share_services", params: {label: "Search", url: "https://example.com/?q=${title}"}.to_json, headers: json
    assert_response :created
    id = JSON.parse(response.body)["id"]

    patch "/v3/custom_share_services/#{id}", params: {label: "Find"}.to_json, headers: json
    assert_equal "Find", JSON.parse(response.body)["label"]

    get "/v3/custom_share_services", headers: bearer
    assert_equal [["Find", "https://example.com/?q=${title}"]], JSON.parse(response.body)["data"].map { it.values_at("label", "url") }

    post "/v3/custom_share_services", params: {label: "", url: "x"}.to_json, headers: json
    assert_response :unprocessable_content

    delete "/v3/custom_share_services/#{id}", headers: bearer
    assert_response :no_content
  end

  private

  def start_instapaper_authorization
    post "/v3/share_services/instapaper/authorization", params: {return_to: "feedbin-test://share-services"}.to_json, headers: json
    assert_response :created
    URI.parse(JSON.parse(response.body)["authorize_url"])
  end

  def bearer
    {"Authorization" => "Bearer #{@token.plaintext_token}"}
  end

  def json
    bearer.merge("Content-Type" => "application/json")
  end
end
