require "test_helper"

class ApiV3FeedsTest < ActionDispatch::IntegrationTest
  setup do
    host! "api.example.com"
    @user = users(:new)
    @user.setting_on!(:api_v3)
    @feeds = 2.times.map { |i| Feed.create!(feed_url: "https://example#{i}.com/feed", host: "example#{i}.com", title: "Example #{i}") }
    @feeds.each { @user.subscriptions.create!(feed: _1) }
    application = @user.oauth_applications.create!(name: "Reader", redirect_uri: "")
    @token = application.access_tokens.create!(resource_owner_id: @user.id, scopes: "read write account")
  end

  test "lists the user's feeds ascending by id with an etag and no meta" do
    get "/v3/feeds", headers: bearer

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "list", body["object"]
    assert_nil body["page"]
    assert_nil body["meta"]
    assert_equal @feeds.map(&:id), body["data"].map { _1["id"] }
    assert_equal ["feed"], body["data"].map { _1["object"] }.uniq
    assert response.headers["ETag"].start_with?(%("feeds:#{@user.id}:))
  end

  test "returns 304 until a feed changes or the set of feeds changes" do
    get "/v3/feeds", headers: bearer
    etag = response.headers["ETag"]

    get "/v3/feeds", headers: bearer.merge("If-None-Match" => etag)
    assert_response :not_modified

    @feeds.first.update!(title: "Renamed", updated_at: 1.minute.from_now)
    get "/v3/feeds", headers: bearer.merge("If-None-Match" => etag)
    assert_response :success
    etag = response.headers["ETag"]

    @user.subscriptions.create!(feed: Feed.create!(feed_url: "https://example9.com/feed", title: "Nine"))
    get "/v3/feeds", headers: bearer.merge("If-None-Match" => etag)
    assert_response :success
    assert_equal 3, JSON.parse(response.body)["data"].size
  end

  test "leaves out feeds the user does not subscribe to" do
    other = Feed.create!(feed_url: "https://other.example/feed", title: "Other")
    users(:ben).subscriptions.create!(feed: other)

    get "/v3/feeds", headers: bearer

    assert_equal @feeds.map(&:id), JSON.parse(response.body)["data"].map { _1["id"] }
  end

  test "lists a feed the user only has starred entries from" do
    kept, subscribed = @feeds
    StarredEntry.create_from_owners(@user, entry_in(kept))
    StarredEntry.create_from_owners(@user, entry_in(subscribed))
    @user.subscriptions.find_by!(feed: kept).destroy!

    get "/v3/feeds", headers: bearer

    assert_response :success
    assert_equal [kept.id, subscribed.id].sort, JSON.parse(response.body)["data"].map { _1["id"] }
  end

  test "the etag moves when a star adds a feed" do
    other = Feed.create!(feed_url: "https://other.example/feed", host: "other.example", title: "Other")
    get "/v3/feeds", headers: bearer
    etag = response.headers["ETag"]
    assert_equal @feeds.map(&:id), JSON.parse(response.body)["data"].map { _1["id"] }

    get "/v3/feeds", headers: bearer.merge("If-None-Match" => etag)
    assert_response :not_modified

    StarredEntry.create_from_owners(@user, entry_in(other))

    get "/v3/feeds", headers: bearer.merge("If-None-Match" => etag)
    assert_response :success
    refute_equal etag, response.headers["ETag"]
    assert_includes JSON.parse(response.body)["data"].map { _1["id"] }, other.id
  end

  test "the etag moves when the last star from a feed is removed" do
    other = Feed.create!(feed_url: "https://other.example/feed", host: "other.example", title: "Other")
    starred = StarredEntry.create_from_owners(@user, entry_in(other))
    get "/v3/feeds", headers: bearer
    etag = response.headers["ETag"]
    assert_includes JSON.parse(response.body)["data"].map { _1["id"] }, other.id

    starred.destroy!

    get "/v3/feeds", headers: bearer.merge("If-None-Match" => etag)
    assert_response :success
    refute_equal etag, response.headers["ETag"]
    assert_equal @feeds.map(&:id), JSON.parse(response.body)["data"].map { _1["id"] }
  end

  private

  def entry_in(feed)
    feed.entries.create!(title: "Kept", url: "#{feed.feed_url}/1", public_id: SecureRandom.hex, entry_id: SecureRandom.hex)
  end

  def bearer
    {"Authorization" => "Bearer #{@token.plaintext_token}"}
  end
end
