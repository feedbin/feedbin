require "test_helper"

class ApiV3FeedsReadsTest < ActionDispatch::IntegrationTest
  setup do
    host! "api.example.com"
    @user = users(:new)
    @user.setting_on!(:api_v3)
    @feed = Feed.create!(feed_url: "https://example.com/feed", host: "example.com", title: "Example", site_url: "https://example.com")
    @user.subscriptions.create!(feed: @feed)
    @entries = 3.times.map do |i|
      @feed.entries.create!(title: "E#{i}", url: "https://example.com/#{i}", public_id: SecureRandom.hex, entry_id: SecureRandom.hex, created_at: (3 - i).hours.ago, published: (10 - i).days.ago)
    end
    @other = Feed.create!(feed_url: "https://other.example/feed", title: "Other")
    @other_entry = @other.entries.create!(title: "x", url: "https://other.example/1", public_id: SecureRandom.hex, entry_id: SecureRandom.hex)
    application = @user.oauth_applications.create!(name: "Reader", redirect_uri: "")
    @token = application.access_tokens.create!(resource_owner_id: @user.id, scopes: "read write account")
  end

  test "shows a readable feed, 403 for an unreadable one, 404 for none" do
    get "/v3/feeds/#{@feed.id}", headers: bearer
    assert_response :success
    assert_equal ["feed", @feed.id], JSON.parse(response.body).values_at("object", "id")

    get "/v3/feeds/#{@other.id}", headers: bearer
    assert_response :forbidden
    assert_equal "not_readable", JSON.parse(response.body)["code"]

    StarredEntry.create_from_owners(@user, @other_entry)
    get "/v3/feeds/#{@other.id}", headers: bearer
    assert_response :success

    get "/v3/feeds/0", headers: bearer
    assert_response :not_found
  end

  test "lists a feed's entries newest first with the timeline's filters and cursor" do
    UnreadEntry.where(user_id: @user.id).delete_all
    UnreadEntry.create_from_owners(@user, @entries.first)

    get "/v3/feeds/#{@feed.id}/entries", params: {limit: 2}, headers: bearer
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @entries.reverse.first(2).map(&:id), body["data"].map { _1["id"] }
    assert body["meta"]["as_of"].present?
    refute body["meta"].key?("arrivals_cursor")

    get body["page"]["next_url"].delete_prefix("http://api.example.com"), headers: bearer
    assert_equal [@entries.first.id], JSON.parse(response.body)["data"].map { _1["id"] }

    get "/v3/feeds/#{@feed.id}/entries", params: {read: "false"}, headers: bearer
    assert_equal [@entries.first.id], JSON.parse(response.body)["data"].map { _1["id"] }

    get "/v3/feeds/#{@other.id}/entries", headers: bearer
    assert_response :forbidden
  end

  test "looks up a feed by url without a token" do
    stub_request(:any, /./).to_return(status: 404)
    get "/v3/feeds/lookup", params: {url: @feed.feed_url}
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @feed.id, body["id"]
    assert_equal @entries.reverse.map(&:id), body["entries"].map { _1["id"] }
    refute body.key?("meta")

    get "/v3/feeds/lookup", params: {url: @feed.feed_url, ids: "#{@entries.first.id},#{@other_entry.id}"}
    assert_equal [@entries.first.id], JSON.parse(response.body)["entries"].map { _1["id"] }

    get "/v3/feeds/lookup", params: {url: @feed.feed_url, changed_after: 2.5.hours.ago.iso8601}
    assert_equal @entries.last(2).reverse.map(&:id), JSON.parse(response.body)["entries"].map { _1["id"] }

    get "/v3/feeds/lookup", params: {url: @feed.feed_url, changed_after: "yesterday"}
    assert_response :unprocessable_content
    get "/v3/feeds/lookup"
    assert_response :unprocessable_content
  end

  test "discovers an unknown feed and 404s when there is none" do
    new_feed = Feed.create!(feed_url: "https://new.example/feed", title: "New")
    FeedFinder.stub(:feeds, [new_feed]) do
      get "/v3/feeds/lookup", params: {url: "https://new.example"}
    end
    assert_response :success
    assert_equal new_feed.id, JSON.parse(response.body)["id"]

    FeedFinder.stub(:feeds, []) do
      get "/v3/feeds/lookup", params: {url: "https://nothing.example"}
    end
    assert_response :not_found
  end

  private

  def bearer
    {"Authorization" => "Bearer #{@token.plaintext_token}"}
  end
end
