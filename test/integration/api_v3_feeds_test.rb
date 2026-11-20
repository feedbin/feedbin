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
    assert_match(/\AW\/"\h+"\z/, response.headers["ETag"])
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

  test "lists the feed of a recently read entry" do
    feed = @feeds.first
    RecentlyReadEntry.create!(user: @user, entry: entry_in(feed))
    @user.subscriptions.find_by!(feed: feed).destroy!

    get "/v3/feeds", headers: bearer
    assert_includes JSON.parse(response.body)["data"].map { _1["id"] }, feed.id

    get "/v3/feeds/#{feed.id}", headers: bearer
    assert_response :success
  end

  test "lists the feed of a recently played and a queued entry" do
    played, queued = 2.times.map { |i| Feed.create!(feed_url: "https://pod#{i}.example/feed", host: "pod#{i}.example", title: "Pod #{i}") }
    RecentlyPlayedEntry.create!(user: @user, entry: entry_in(played))
    QueuedEntry.create!(user: @user, entry: entry_in(queued), feed: queued)

    get "/v3/feeds", headers: bearer

    ids = JSON.parse(response.body)["data"].map { _1["id"] }
    assert_includes ids, played.id
    assert_includes ids, queued.id
  end

  test "the etag holds when recently read changes within listed feeds" do
    entry = entry_in(@feeds.first)
    get "/v3/feeds", headers: bearer
    etag = response.headers["ETag"]

    RecentlyReadEntry.create!(user: @user, entry: entry)

    get "/v3/feeds", headers: bearer.merge("If-None-Match" => etag)
    assert_response :not_modified
  end

  test "the etag moves when a recently read entry adds a feed" do
    other = Feed.create!(feed_url: "https://other.example/feed", host: "other.example", title: "Other")
    entry = entry_in(other)
    get "/v3/feeds", headers: bearer
    etag = response.headers["ETag"]

    RecentlyReadEntry.create!(user: @user, entry: entry)

    get "/v3/feeds", headers: bearer.merge("If-None-Match" => etag)
    assert_response :success
    assert_includes JSON.parse(response.body)["data"].map { _1["id"] }, other.id
  end

  test "expand=daily_entry_counts gives every listed feed its last 90 days, with the body's etag" do
    FeedStat.create!(feed: @feeds.first, day: Date.current, entries_count: 4)
    FeedStat.create!(feed: @feeds.first, day: 89.days.ago.to_date, entries_count: 2)
    FeedStat.create!(feed: @feeds.first, day: 90.days.ago.to_date, entries_count: 9)

    get "/v3/feeds", params: {expand: "daily_entry_counts"}, headers: bearer
    assert_response :success
    counts = JSON.parse(response.body)["data"].to_h { [_1["id"], _1["daily_entry_counts"]] }
    assert_equal [2, *Array.new(88, 0), 4], counts[@feeds.first.id]
    assert_equal Array.new(90, 0), counts[@feeds.last.id]
    etag = response.headers["ETag"]

    get "/v3/feeds", params: {expand: "daily_entry_counts"}, headers: bearer.merge("If-None-Match" => etag)
    assert_response :not_modified

    # a feed publishing moves the counts, and the etag with them
    FeedStat.find_by!(feed: @feeds.first, day: Date.current).update!(entries_count: 5)
    get "/v3/feeds", params: {expand: "daily_entry_counts"}, headers: bearer.merge("If-None-Match" => etag)
    assert_response :success

    get "/v3/feeds", headers: bearer
    refute JSON.parse(response.body)["data"].first.key?("daily_entry_counts")

    get "/v3/feeds", params: {expand: "tags"}, headers: bearer
    assert_response :unprocessable_entity
  end

  private

  def entry_in(feed)
    feed.entries.create!(title: "Kept", url: "#{feed.feed_url}/1", public_id: SecureRandom.hex, entry_id: SecureRandom.hex)
  end

  def bearer
    {"Authorization" => "Bearer #{@token.plaintext_token}"}
  end
end
