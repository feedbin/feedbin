require "test_helper"
require "minitest/stub_any_instance"

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

    finding([@found, @second]) do
      post "/v3/subscriptions/new", params: {q: "https://marco.example"}.to_json, headers: json
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "list", body["object"]
    assert_equal [@found.id, @second.id], body["data"].map { it["id"] }
    assert_equal ["feed", "feed"], body["data"].map { it["object"] }
    assert_equal Api::V3::FeedSerializer.new(@found).to_h.keys.map(&:to_s) + %w[subscription_id daily_entry_counts], body["data"].first.keys
    assert_equal [nil, subscription.id], body["data"].map { it["subscription_id"] }
    counts = body["data"].first["daily_entry_counts"]
    assert_equal 30, counts.size
    assert_equal [2, 4], [counts.first, counts.last]
    assert_equal 6, counts.sum
    assert_nil body["tags"]
    assert_equal 1, @user.subscriptions.count
  end

  test "a single result is still a list" do
    finding([@found]) do
      post "/v3/subscriptions/new", params: {q: "marco.example"}.to_json, headers: json
    end
    assert_response :success
    assert_equal [@found.id], JSON.parse(response.body)["data"].map { it["id"] }
    refute @user.subscriptions.exists?(feed: @found)
  end

  test "words search known feeds" do
    Feed.stub(:search, Feed.where(id: @found.id)) do
      FeedFinder.stub(:new, ->(*, **) { flunk "words must not be fetched" }) do
        post "/v3/subscriptions/new", params: {q: "marco arment"}.to_json, headers: json
      end
    end
    assert_response :success
    assert_equal [@found.id], JSON.parse(response.body)["data"].map { it["id"] }
  end

  test "a subscription to a feed that redirected to a candidate counts" do
    old = Feed.create!(feed_url: "https://old.example/rss", redirected_to: @found.feed_url)
    subscription = @user.subscriptions.create!(feed: old)
    finding([@found]) do
      post "/v3/subscriptions/new", params: {q: "https://marco.example"}.to_json, headers: json
    end
    assert_equal [subscription.id], JSON.parse(response.body)["data"].map { it["subscription_id"] }
  end

  test "nothing found is no_feed_found, for words and for a page without a feed" do
    Feed.stub(:search, Feed.none) do
      post "/v3/subscriptions/new", params: {q: "daring fireball"}.to_json, headers: json
    end
    assert_problem "no_feed_found", detail: /daring fireball/

    stub_request(:get, "http://plain.example/").to_return(body: "<html><body><a href=\"/about\">About</a></body></html>", headers: {"Content-Type" => "text/html"})
    stub_guesses("http://plain.example")
    post "/v3/subscriptions/new", params: {q: "plain.example"}.to_json, headers: json
    assert_problem "no_feed_found"
  end

  test "a file that is neither a feed nor a page is not_a_feed" do
    stub_request(:get, "https://img.example/logo.png").to_return(body: "\x89PNG\r\n\x1A\n\x00\x00", headers: {"Content-Type" => "image/png"})
    stub_guesses("https://img.example")
    post "/v3/subscriptions/new", params: {q: "https://img.example/logo.png"}.to_json, headers: json
    assert_problem "not_a_feed"
  end

  test "an error from the site is upstream_error with its http_code" do
    {404 => {}, 500 => {}, 401 => {"WWW-Authenticate" => "Bearer"}}.each do |status, headers|
      stub_request(:get, "https://broken.example/feed").to_return(status: status, headers: headers)
      post "/v3/subscriptions/new", params: {q: "https://broken.example/feed"}.to_json, headers: json
      body = assert_problem("upstream_error", detail: /broken\.example/)
      assert_equal status, body["http_code"]
    end
  end

  test "a site that cannot be reached is unreachable" do
    stub_request(:get, "https://slow.example/feed").to_timeout
    post "/v3/subscriptions/new", params: {q: "https://slow.example/feed"}.to_json, headers: json
    assert_problem "unreachable", detail: /slow\.example/

    stub_request(:get, "https://down.example/feed").to_raise(HTTP::ConnectionError)
    post "/v3/subscriptions/new", params: {q: "https://down.example/feed"}.to_json, headers: json
    assert_problem "unreachable"
  end

  test "an address that does not parse is invalid_url" do
    ["http://", "http://exa mple.com/feed", "http://:80/feed"].each do |q|
      post "/v3/subscriptions/new", params: {q: q}.to_json, headers: json
      assert_problem "invalid_url"
    end
  end

  test "expand=tags adds the user's tags" do
    @user.subscriptions.create!(feed: @second)
    @second.tag(["Apple"], @user)
    finding([@found]) do
      post "/v3/subscriptions/new?expand=tags", params: {q: "https://marco.example"}.to_json, headers: json
    end
    tags = JSON.parse(response.body)["tags"]
    assert_equal [["tag", "Apple"]], tags.map { it.values_at("object", "name") }

    post "/v3/subscriptions/new?expand=feed", params: {q: "x.example"}.to_json, headers: json
    assert_response :unprocessable_content
  end

  test "q is required" do
    post "/v3/subscriptions/new", params: {}.to_json, headers: json
    assert_response :unprocessable_content
    assert_equal ["/q", "missing"], JSON.parse(response.body)["errors"].first.values_at("pointer", "code")

    post "/v3/subscriptions/new", params: {q: " "}.to_json, headers: json
    assert_response :unprocessable_content
    assert_equal ["/q", "missing"], JSON.parse(response.body)["errors"].first.values_at("pointer", "code")
  end

  test "find is POST only" do
    get "/v3/subscriptions/new", params: {q: "https://marco.example"}, headers: bearer
    assert_response :not_found
  end

  test "a protected feed asks for credentials, then says they were wrong" do
    stub_request(:get, "https://private.example/rss").to_return(status: 401, headers: {"WWW-Authenticate" => "Basic realm=\"feed\""})

    post "/v3/subscriptions/new", params: {q: "https://private.example/rss"}.to_json, headers: json
    assert_problem "credentials_required"

    post "/v3/subscriptions/new", params: {q: "https://private.example/rss", feed_username: "me", feed_password: "wrong"}.to_json, headers: json
    assert_problem "credentials_invalid"

    post "/v3/subscriptions/new", params: {q: "https://me:wrong@private.example/rss"}.to_json, headers: json
    assert_problem "credentials_invalid"
  end

  test "the POST passes credentials to discovery" do
    sent = nil
    finder = ->(url, **args) {
      sent = [url, args]
      Struct.new(:find, :response).new([@found], nil)
    }
    FeedFinder.stub(:new, finder) do
      post "/v3/subscriptions/new?expand=tags", params: {q: "https://private.example/rss", feed_username: "me", feed_password: "right"}.to_json, headers: json
    end
    assert_response :success
    assert_equal ["https://private.example/rss", {username: "me", password: "right", raise_errors: true}], sent
    body = JSON.parse(response.body)
    assert_equal [@found.id], body["data"].map { it["id"] }
    assert_equal [], body["tags"]
  end

  test "found candidates can be subscribed by the feed_url returned" do
    finding([@found, @second]) do
      post "/v3/subscriptions/new", params: {q: "https://marco.example"}.to_json, headers: json
    end
    urls = JSON.parse(response.body)["data"].map { it["feed_url"] }
    post "/v3/subscriptions", params: {feeds: urls.map { {feed_url: it} }}.to_json, headers: json
    assert_response :success
    assert_equal [@found.id, @second.id], JSON.parse(response.body)["applied"]
  end

  private

  def finding(feeds, &)
    FeedFinder.stub_any_instance(:find, feeds, &)
  end

  # Source::Guess tries /rss and /feed when a page links no feed.
  def stub_guesses(origin)
    %w[/rss /feed].each { stub_request(:get, "#{origin}#{it}").to_return(status: 404) }
  end

  def assert_problem(code, detail: nil)
    assert_response :unprocessable_content
    body = JSON.parse(response.body)
    assert_equal code, body["code"], body.inspect
    assert_equal "https://api.feedbin.com/errors/#{code}", body["type"]
    assert_match detail, body["detail"] if detail
    body
  end

  def bearer
    {"Authorization" => "Bearer #{@token.plaintext_token}"}
  end

  def json
    bearer.merge("Content-Type" => "application/json")
  end
end
