require "test_helper"

class ApiV3SubscriptionCandidatesTest < ActionDispatch::IntegrationTest
  setup do
    host! "api.example.com"
    @user = users(:new)
    @user.setting_on!(:api_v3)
    application = @user.oauth_applications.create!(name: "Reader", redirect_uri: "")
    @token = application.access_tokens.create!(resource_owner_id: @user.id, scopes: "read write account")
    @found = Feed.create!(feed_url: "https://marco.example/rss", title: "Marco", site_url: "https://marco.example")
    @second = Feed.create!(feed_url: "https://marco.example/podcast", title: "Marco Podcast")
  end

  test "a url lists every feed found, with subscription and daily counts, and subscribes to nothing" do
    subscription = @user.subscriptions.create!(feed: @second)
    FeedStat.create!(feed: @found, day: Date.current, entries_count: 4)
    FeedStat.create!(feed: @found, day: 29.days.ago.to_date, entries_count: 2)
    FeedStat.create!(feed: @found, day: 30.days.ago.to_date, entries_count: 9)

    FeedFinder.stub(:feeds, [@found, @second]) do
      get "/v3/subscriptions/new", params: {q: "https://marco.example"}, headers: bearer
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "list", body["object"]
    assert_equal [@found.id, @second.id], body["data"].map { it["feed"]["id"] }
    assert_equal "feed", body["data"].first["feed"]["object"]
    assert_equal [nil, subscription.id], body["data"].map { it["subscription_id"] }
    counts = body["data"].first["daily_entry_counts"]
    assert_equal 30, counts.size
    assert_equal [2, 4], [counts.first, counts.last]
    assert_equal 6, counts.sum
    assert_equal [nil, nil], body["data"].map { it["id"] }
    assert_nil body["tags"]
    assert_equal 1, @user.subscriptions.count
  end

  test "a single result is still a list" do
    FeedFinder.stub(:feeds, [@found]) do
      get "/v3/subscriptions/new", params: {q: "marco.example"}, headers: bearer
    end
    assert_response :success
    assert_equal [@found.id], JSON.parse(response.body)["data"].map { it["feed"]["id"] }
    refute @user.subscriptions.exists?(feed: @found)
  end

  test "words search known feeds" do
    Feed.stub(:search, Feed.where(id: @found.id)) do
      FeedFinder.stub(:feeds, ->(*) { flunk "words must not be fetched" }) do
        get "/v3/subscriptions/new", params: {q: "marco arment"}, headers: bearer
      end
    end
    assert_response :success
    assert_equal [@found.id], JSON.parse(response.body)["data"].map { it["feed"]["id"] }
  end

  test "a subscription to a feed that redirected to a candidate counts" do
    old = Feed.create!(feed_url: "https://old.example/rss", redirected_to: @found.feed_url)
    subscription = @user.subscriptions.create!(feed: old)
    FeedFinder.stub(:feeds, [@found]) do
      get "/v3/subscriptions/new", params: {q: "https://marco.example"}, headers: bearer
    end
    assert_equal [subscription.id], JSON.parse(response.body)["data"].map { it["subscription_id"] }
  end

  test "nothing found is an empty list, including a site that fails" do
    FeedFinder.stub(:feeds, []) do
      get "/v3/subscriptions/new", params: {q: "https://nothing.example"}, headers: bearer
    end
    assert_response :success
    assert_equal [], JSON.parse(response.body)["data"]

    FeedFinder.stub(:feeds, ->(*) { raise Errno::ECONNREFUSED }) do
      get "/v3/subscriptions/new", params: {q: "https://broken.example"}, headers: bearer
    end
    assert_response :success
    assert_equal [], JSON.parse(response.body)["data"]

    Feed.stub(:search, ->(*) { raise Search::Connection::ResponseError, "down" }) do
      get "/v3/subscriptions/new", params: {q: "daring fireball"}, headers: bearer
    end
    assert_response :success
    assert_equal [], JSON.parse(response.body)["data"]
  end

  test "expand=tags adds the user's tags" do
    @user.subscriptions.create!(feed: @second)
    @second.tag(["Apple"], @user)
    FeedFinder.stub(:feeds, [@found]) do
      get "/v3/subscriptions/new", params: {q: "https://marco.example", expand: "tags"}, headers: bearer
    end
    tags = JSON.parse(response.body)["tags"]
    assert_equal [["tag", "Apple"]], tags.map { it.values_at("object", "name") }

    get "/v3/subscriptions/new", params: {q: "x.example", expand: "feed"}, headers: bearer
    assert_response :unprocessable_content
  end

  test "q is required" do
    get "/v3/subscriptions/new", headers: bearer
    assert_response :unprocessable_content
    assert_equal ["q", "missing"], JSON.parse(response.body)["errors"].first.values_at("pointer", "code")

    post "/v3/subscriptions/new", params: {q: " "}.to_json, headers: json
    assert_response :unprocessable_content
    assert_equal ["/q", "missing"], JSON.parse(response.body)["errors"].first.values_at("pointer", "code")
  end

  test "the GET refuses feed credentials" do
    get "/v3/subscriptions/new", params: {q: "https://marco.example", feed_password: "secret"}, headers: bearer
    assert_response :unprocessable_content
    assert_equal "feed_password", JSON.parse(response.body)["errors"].first["pointer"]

    FeedFinder.stub(:feeds, ->(*) { flunk "credentials in a GET must not be used" }) do
      get "/v3/subscriptions/new", params: {q: "https://me:secret@marco.example/rss"}, headers: bearer
    end
    assert_response :unprocessable_content
    assert_equal ["q", "invalid_value"], JSON.parse(response.body)["errors"].first.values_at("pointer", "code")
  end

  test "a protected feed asks for credentials, then says they were wrong" do
    finder = ->(*, **) { raise unauthorized }
    FeedFinder.stub(:feeds, finder) do
      get "/v3/subscriptions/new", params: {q: "https://private.example/rss"}, headers: bearer
      assert_response :unprocessable_content
      assert_equal "credentials_required", JSON.parse(response.body)["code"]

      post "/v3/subscriptions/new", params: {q: "https://private.example/rss", feed_username: "me", feed_password: "wrong"}.to_json, headers: json
      assert_response :unprocessable_content
      assert_equal "credentials_invalid", JSON.parse(response.body)["code"]

      post "/v3/subscriptions/new", params: {q: "https://me:wrong@private.example/rss"}.to_json, headers: json
      assert_equal "credentials_invalid", JSON.parse(response.body)["code"]
    end
  end

  test "the POST passes credentials to discovery" do
    sent = nil
    finder = ->(url, **args) {
      sent = [url, args]
      [@found]
    }
    FeedFinder.stub(:feeds, finder) do
      post "/v3/subscriptions/new?expand=tags", params: {q: "https://private.example/rss", feed_username: "me", feed_password: "right"}.to_json, headers: json
    end
    assert_response :success
    assert_equal ["https://private.example/rss", {username: "me", password: "right"}], sent
    body = JSON.parse(response.body)
    assert_equal [@found.id], body["data"].map { it["feed"]["id"] }
    assert_equal [], body["tags"]
  end

  test "offered candidates can be subscribed by id" do
    FeedFinder.stub(:feeds, [@found, @second]) do
      get "/v3/subscriptions/new", params: {q: "https://marco.example"}, headers: bearer
    end
    post "/v3/subscriptions", params: {feeds: [{feed_id: @found.id}, {feed_id: @second.id}]}.to_json, headers: json
    assert_response :success
    assert_equal [@found.id, @second.id], JSON.parse(response.body)["applied"]
  end

  private

  def unauthorized
    response = Struct.new(:headers).new({www_authenticate: "Basic realm=\"feed\""})
    Feedkit::Unauthorized.new("401", response)
  end

  def bearer
    {"Authorization" => "Bearer #{@token.plaintext_token}"}
  end

  def json
    bearer.merge("Content-Type" => "application/json")
  end
end
