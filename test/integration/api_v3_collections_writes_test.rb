require "test_helper"
require "minitest/stub_any_instance"

class ApiV3CollectionsWritesTest < ActionDispatch::IntegrationTest
  setup do
    host! "api.example.com"
    @user = users(:new)
    @user.setting_on!(:api_v3)
    @feed = Feed.create!(feed_url: "https://example.com/feed", title: "Example")
    @user.subscriptions.create!(feed: @feed)
    UnreadEntry.where(user_id: @user.id).delete_all
    @entries = 3.times.map do |i|
      @feed.entries.create!(title: "E#{i}", url: "https://example.com/#{i}", public_id: SecureRandom.hex, entry_id: SecureRandom.hex, created_at: (3 - i).hours.ago, data: {"enclosure_url" => "https://example.com/#{i}.mp3", "enclosure_type" => "audio/mpeg"})
    end
    @other = Feed.create!(feed_url: "https://other.example/feed").entries.create!(title: "x", url: "https://other.example/1", public_id: SecureRandom.hex, entry_id: SecureRandom.hex)
    application = @user.oauth_applications.create!(name: "Reader", redirect_uri: "")
    @token = application.access_tokens.create!(resource_owner_id: @user.id, scopes: "read write account")
  end

  test "lists the sidebar with hidden flags and an etag" do
    @user.setting_on!(:hide_updated)
    search = @user.saved_searches.create!(name: "Swift", query: "swift")

    get "/v3/collections", headers: bearer

    assert_response :success
    body = JSON.parse(response.body)
    assert_nil body["meta"]
    rows = body["data"].index_by { _1["id"] }
    assert_equal %W[unread all starred queue recently_read updated recently_played search_#{search.id}], body["data"].map { _1["id"] }
    assert_equal({"object" => "collection", "id" => "unread", "kind" => "system", "title" => "Unread", "sort" => "received_desc", "hidden" => false, "writes" => ["state"], "query" => nil}, rows["unread"])
    assert_equal [true, true, true], [rows["queue"]["hidden"], rows["recently_played"]["hidden"], rows["updated"]["hidden"]]
    assert_equal %w[add remove update clear], rows["queue"]["writes"]
    assert_equal({"kind" => "search", "title" => "Swift", "sort" => "published_desc", "writes" => [], "query" => "swift"}, rows["search_#{search.id}"].slice("kind", "title", "sort", "writes", "query"))
    etag = response.headers["ETag"]

    get "/v3/collections", headers: bearer.merge("If-None-Match" => etag)
    assert_response :not_modified

    QueuedEntry.create!(user_id: @user.id, entry_id: @entries.first.id, feed_id: @feed.id)
    get "/v3/collections", headers: bearer.merge("If-None-Match" => etag)
    assert_response :success
    assert_equal false, JSON.parse(response.body)["data"].find { _1["id"] == "queue" }["hidden"]
  end

  test "serves ids for every list collection" do
    entry = @entries.first
    UpdatedEntry.create!(user_id: @user.id, entry_id: entry.id, feed_id: @feed.id, published: entry.published, updated: Time.now)
    RecentlyReadEntry.create_from_owners(@user, entry.id)
    RecentlyPlayedEntry.create!(user_id: @user.id, entry_id: entry.id)
    QueuedEntry.create!(user_id: @user.id, entry_id: entry.id, feed_id: @feed.id)

    %w[updated recently_read recently_played queue].each do |id|
      get "/v3/collections/#{id}/ids", headers: bearer
      assert_response :success, id
      assert_equal [entry.id], JSON.parse(response.body)["data"], id
      assert response.headers["ETag"].start_with?(%("#{id}:#{@user.id}:)), id
    end

    get "/v3/collections/all/ids", headers: bearer
    assert_response :not_found
  end

  test "a saved search's ids are its newest unread matches, ascending" do
    search = @user.saved_searches.create!(name: "Swift", query: "swift")
    matches = swift_entries(4)
    UnreadEntry.where(user_id: @user.id, entry_id: matches.first.id).delete_all

    Api::V3::Collection.stub_const(:SEARCH_IDS_LIMIT, 2) do
      get "/v3/collections/search_#{search.id}/ids", headers: bearer
    end

    assert_response :success
    assert_equal matches.last(2).map(&:id).sort, JSON.parse(response.body)["data"]
    assert response.headers["ETag"].start_with?(%("search_#{search.id}:#{@user.id}:))

    get "/v3/collections/search_999999/ids", headers: bearer
    assert_response :not_found
  end

  test "every saved search has ids, not only the first 50" do
    matches = swift_entries(1)
    searches = 51.times.map { @user.saved_searches.create!(name: "Swift #{_1}", query: "swift") }

    get "/v3/collections/search_#{searches.last.id}/ids", headers: bearer

    assert_equal [matches.first.id], JSON.parse(response.body)["data"]
  end

  test "a saved search's ids etag moves with stars and subscriptions" do
    search = @user.saved_searches.create!(name: "Swift", query: "swift is:starred")
    matches = swift_entries(1)
    get "/v3/collections/search_#{search.id}/ids", headers: bearer
    etag = response.headers["ETag"]

    StarredEntry.create_from_owners(@user, matches.first)
    get "/v3/collections/search_#{search.id}/ids", headers: bearer.merge("If-None-Match" => etag)
    assert_response :success
    etag = response.headers["ETag"]

    @user.subscriptions.find_by!(feed: @feed).destroy
    get "/v3/collections/search_#{search.id}/ids", headers: bearer.merge("If-None-Match" => etag)
    assert_response :success
  end

  test "a saved search with no updated_at still lists" do
    search = @user.saved_searches.create!(name: "Swift", query: "swift")
    search.update_column(:updated_at, nil)

    get "/v3/collections/search_#{search.id}/ids", headers: bearer
    assert_response :success

    get "/v3/saved_searches", headers: bearer
    assert_response :success
  end

  test "a saved search whose query no longer parses has no ids" do
    swift_entries(1)
    search = @user.saved_searches.create!(name: "Broken", query: "swift")
    search.update_column(:query, "title:(")

    get "/v3/collections/search_#{search.id}/ids", headers: bearer

    assert_response :success
    assert_equal [], JSON.parse(response.body)["data"]
  end

  test "lists a collection's entries in its order with membership, paginated" do
    @entries.each_with_index { |entry, i| StarredEntry.create!(user_id: @user.id, entry_id: entry.id, feed_id: @feed.id, published: entry.published, created_at: (3 - i).minutes.ago) }

    get "/v3/collections/starred/entries", params: {limit: 2}, headers: bearer
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @entries.reverse.first(2).map(&:id), body["data"].map { _1["id"] }
    assert_equal ["added_at"], body["data"].first["membership"].keys
    assert body["meta"]["as_of"].present?
    assert body["page"]["next_url"].present?

    get body["page"]["next_url"].delete_prefix("http://api.example.com"), headers: bearer
    second = JSON.parse(response.body)
    assert_equal [@entries.first.id], second["data"].map { _1["id"] }
    assert_nil second["page"]["next_cursor"]
  end

  test "the queue's entries carry the full membership in manual order" do
    QueuedEntry.create!(user_id: @user.id, entry_id: @entries.first.id, feed_id: @feed.id, order: 2, progress: 30, duration: 600, skipped_chapters: [1])
    QueuedEntry.create!(user_id: @user.id, entry_id: @entries.last.id, feed_id: @feed.id, order: 1)

    get "/v3/collections/queue/entries", headers: bearer
    body = JSON.parse(response.body)
    assert_equal [@entries.last.id, @entries.first.id], body["data"].map { _1["id"] }
    membership = body["data"].last["membership"]
    assert_equal %w[added_at sort_order progress_in_seconds duration_in_seconds playlist_id skipped_chapters], membership.keys
    assert_equal [2, 30, 600, nil, [1]], membership.values_at("sort_order", "progress_in_seconds", "duration_in_seconds", "playlist_id", "skipped_chapters")

    get "/v3/collections/all/entries", headers: bearer
    assert_equal @entries.reverse.map(&:id), JSON.parse(response.body)["data"].map { _1["id"] }
    refute JSON.parse(response.body)["data"].first.key?("membership")
  end

  test "adds to recently read and recently played, skipping what the user cannot touch" do
    post "/v3/collections/recently_read/entries", params: {ids: [@entries.first.id, @other.id, 999_999_999]}.to_json, headers: json
    assert_response :success
    assert_equal({"applied" => [@entries.first.id], "skipped" => [{"id" => @other.id, "reason" => "not_subscribed"}, {"id" => 999_999_999, "reason" => "not_found"}]}, JSON.parse(response.body))
    assert_equal [@entries.first.id], @user.recently_read_entries.pluck(:entry_id)

    post "/v3/collections/recently_read/entries", params: {ids: [@entries.first.id]}.to_json, headers: json
    assert_equal [@entries.first.id], JSON.parse(response.body)["applied"]

    post "/v3/collections/recently_played/entries", params: {ids: [@entries.last.id]}.to_json, headers: json
    assert_equal [@entries.last.id], @user.recently_played_entries.pluck(:entry_id)

    post "/v3/collections/unread/entries", params: {ids: [@entries.first.id]}.to_json, headers: json
    assert_response :unprocessable_content
    post "/v3/collections/nope/entries", params: {ids: [1]}.to_json, headers: json
    assert_response :not_found
  end

  test "queues episodes of subscribed podcasts into a playlist" do
    playlist = @user.playlists.create!(title: "Commute")
    post "/v3/collections/queue/entries", params: {ids: [@entries.first.id], playlist_id: playlist.id}.to_json, headers: json
    assert_equal [{"id" => @entries.first.id, "reason" => "not_subscribed"}], JSON.parse(response.body)["skipped"]

    @user.podcast_subscriptions.create!(feed: @feed, status: :subscribed)
    post "/v3/collections/queue/entries", params: {ids: [@entries.first.id], playlist_id: playlist.id}.to_json, headers: json
    assert_equal [@entries.first.id], JSON.parse(response.body)["applied"]
    assert_equal playlist.id, @user.queued_entries.find_by!(entry_id: @entries.first.id).playlist_id
  end

  test "updates a queue membership field by field with timestamps" do
    @user.podcast_subscriptions.create!(feed: @feed, status: :subscribed)
    queued = QueuedEntry.create!(user_id: @user.id, entry_id: @entries.first.id, feed_id: @feed.id, order: 1)
    queued.update!(progress: 100)
    stored_at = queued.progress_updated_at

    patch "/v3/collections/queue/entries/#{@entries.first.id}", params: {progress_in_seconds: 50, progress_in_seconds_updated_at: (stored_at - 1.minute).iso8601, sort_order: 7, sort_order_updated_at: Time.now.iso8601, duration_in_seconds: 900, skipped_chapters: [2]}.to_json, headers: json
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [100, 7, 900, [2]], body.values_at("progress_in_seconds", "sort_order", "duration_in_seconds", "skipped_chapters")
    assert_equal %w[added_at sort_order progress_in_seconds duration_in_seconds playlist_id skipped_chapters], body.keys

    patch "/v3/collections/queue/entries/#{@entries.first.id}", params: {progress_in_seconds: 50}.to_json, headers: json
    assert_response :unprocessable_content
    assert_equal "/progress_in_seconds_updated_at", JSON.parse(response.body)["errors"].first["pointer"]

    patch "/v3/collections/queue/entries/#{@entries.last.id}", params: {duration_in_seconds: 1}.to_json, headers: json
    assert_response :not_found
  end

  test "reorders the queue in bulk and reports stale writes" do
    rows = @entries.map { QueuedEntry.create!(user_id: @user.id, entry_id: _1.id, feed_id: @feed.id, order: 0) }
    rows.first.update!(order: 5)
    old = (rows.first.order_updated_at - 1.minute).iso8601
    now = Time.now.iso8601

    patch "/v3/collections/queue/entries", params: {entries: [
      {id: @entries.first.id, sort_order: 0, sort_order_updated_at: old},
      {id: @entries[1].id, sort_order: 1, sort_order_updated_at: now},
      {id: @other.id, sort_order: 2, sort_order_updated_at: now}
    ]}.to_json, headers: json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [@entries[1].id], body["applied"]
    assert_equal [{"id" => @entries.first.id, "reason" => "stale_write"}, {"id" => @other.id, "reason" => "not_found"}], body["skipped"]
    assert_equal [5, 1], [rows.first.reload.order, rows[1].reload.order]

    patch "/v3/collections/queue/entries", params: {entries: [{id: @entries[1].id, sort_order: 3}]}.to_json, headers: json
    assert_response :unprocessable_content
  end

  test "removes from and clears the collections that allow it" do
    QueuedEntry.create!(user_id: @user.id, entry_id: @entries.first.id, feed_id: @feed.id)
    delete "/v3/collections/queue/entries/#{@entries.first.id}", headers: bearer
    assert_response :no_content
    delete "/v3/collections/queue/entries/#{@entries.first.id}", headers: bearer
    assert_response :no_content
    assert_equal 0, @user.queued_entries.count

    delete "/v3/collections/recently_read/entries/#{@entries.first.id}", headers: bearer
    assert_response :unprocessable_content

    RecentlyReadEntry.create_from_owners(@user, @entries.first.id)
    RecentlyPlayedEntry.create!(user_id: @user.id, entry_id: @entries.first.id)
    delete "/v3/collections/recently_read/entries", headers: bearer
    assert_response :no_content
    delete "/v3/collections/recently_played/entries", headers: bearer
    assert_response :no_content
    assert_equal [0, 0], [@user.recently_read_entries.count, @user.recently_played_entries.count]

    delete "/v3/collections/starred/entries", headers: bearer
    assert_response :unprocessable_content
  end

  test "records a play of an Airshow episode the reader does not subscribe to" do
    podcast = Feed.create!(feed_url: "https://podcast.example/feed", title: "Podcast")
    episode, queued_episode, stranger = 3.times.map { |i| podcast.entries.create!(title: "Ep #{i}", url: "https://podcast.example/#{i}", public_id: SecureRandom.hex, entry_id: SecureRandom.hex) }
    unrelated = Feed.create!(feed_url: "https://unrelated.example/feed").entries.create!(title: "u", url: "https://unrelated.example/1", public_id: SecureRandom.hex, entry_id: SecureRandom.hex)
    @user.podcast_subscriptions.create!(feed: podcast, status: :subscribed)

    post "/v3/collections/recently_played/entries", params: {ids: [episode.id, unrelated.id]}.to_json, headers: json
    assert_equal [episode.id], JSON.parse(response.body)["applied"]

    @user.podcast_subscriptions.destroy_all
    QueuedEntry.create!(user_id: @user.id, entry_id: queued_episode.id, feed_id: podcast.id)
    post "/v3/collections/recently_played/entries", params: {ids: [queued_episode.id, stranger.id]}.to_json, headers: json
    assert_equal [queued_episode.id], JSON.parse(response.body)["applied"]
  end

  test "queues only into the user's own playlists" do
    @user.podcast_subscriptions.create!(feed: @feed, status: :subscribed)
    foreign = users(:ben).playlists.create!(title: "Theirs")

    post "/v3/collections/queue/entries", params: {ids: [@entries.first.id], playlist_id: foreign.id}.to_json, headers: json
    assert_response :unprocessable_content
    assert_equal "/playlist_id", JSON.parse(response.body)["errors"].first["pointer"]
    refute @user.queued_entries.exists?(entry_id: @entries.first.id)

    QueuedEntry.create!(user_id: @user.id, entry_id: @entries.first.id, feed_id: @feed.id, order: 1)
    patch "/v3/collections/queue/entries/#{@entries.first.id}", params: {playlist_id: foreign.id, playlist_id_updated_at: Time.now.iso8601}.to_json, headers: json
    assert_response :unprocessable_content
    assert_equal "/playlist_id", JSON.parse(response.body)["errors"].first["pointer"]
  end

  test "a queue field stamp without a UTC offset is rejected" do
    @user.podcast_subscriptions.create!(feed: @feed, status: :subscribed)
    QueuedEntry.create!(user_id: @user.id, entry_id: @entries.first.id, feed_id: @feed.id, order: 1)

    patch "/v3/collections/queue/entries/#{@entries.first.id}", params: {sort_order: 3, sort_order_updated_at: "2026-11-02T10:00:00"}.to_json, headers: json

    assert_response :unprocessable_content
    assert_equal "/sort_order_updated_at", JSON.parse(response.body)["errors"].first["pointer"]
  end

  test "adding entries costs a fixed number of queries per id, not a permission lookup each" do
    entries = 55.times.map { |i| @feed.entries.create!(title: "R#{i}", url: "https://example.com/r/#{i}", public_id: SecureRandom.hex, entry_id: SecureRandom.hex) }

    few = count_queries { post "/v3/collections/recently_read/entries", params: {ids: entries.first(5).map(&:id)}.to_json, headers: json }
    many = count_queries { post "/v3/collections/recently_read/entries", params: {ids: entries.last(50).map(&:id)}.to_json, headers: json }

    assert_equal 50, JSON.parse(response.body)["applied"].size
    # Per id, only RecentlyReadEntry.create_from_owners: savepoint, the
    # uniqueness validation, the insert, release. A permission lookup per id
    # made it nine.
    assert_operator (many - few) / 45.0, :<=, 4, "#{few} queries for 5 ids, #{many} for 50"
  end

  test "a bulk row with only an id is applied" do
    @user.podcast_subscriptions.create!(feed: @feed, status: :subscribed)
    QueuedEntry.create!(user_id: @user.id, entry_id: @entries.first.id, feed_id: @feed.id, order: 1)

    patch "/v3/collections/queue/entries", params: {entries: [{id: @entries.first.id}]}.to_json, headers: json

    assert_response :success
    assert_equal({"applied" => [@entries.first.id], "skipped" => []}, JSON.parse(response.body))
  end

  test "an Elasticsearch failure is not an empty id list" do
    search = @user.saved_searches.create!(name: "Swift", query: "swift")
    swift_entries(1)
    rejected = Search::Response.new({"error" => {"type" => "es_rejected_execution_exception"}, "status" => 429})

    Search::Connection.stub_any_instance(:search_after, rejected) do
      assert_raises(Search::Connection::ResponseError) { get "/v3/collections/search_#{search.id}/ids", headers: bearer }
    end
    Search::Connection.stub_any_instance(:search_after, ->(*, **) { raise Search::Connection::ResponseError, "502 from the proxy" }) do
      assert_raises(Search::Connection::ResponseError) { get "/v3/collections/search_#{search.id}/ids", headers: bearer }
    end
  end

  # Elasticsearch indexes after the unread row exists, so an ETag made from
  # versions alone could cache a list missing the entry.
  test "a saved search's ids etag moves when a match is indexed late" do
    search = @user.saved_searches.create!(name: "Swift", query: "swift")
    late = @feed.entries.create!(title: "Swift late", url: "https://example.com/late", public_id: SecureRandom.hex, entry_id: SecureRandom.hex, published: Time.now)
    UnreadEntry.create_from_owners(@user, late)
    get "/v3/collections/search_#{search.id}/ids", headers: bearer
    assert_equal [], JSON.parse(response.body)["data"]
    etag = response.headers["ETag"]

    index_entries([late])
    get "/v3/collections/search_#{search.id}/ids", headers: bearer.merge("If-None-Match" => etag)

    assert_response :success
    assert_equal [late.id], JSON.parse(response.body)["data"]
  end

  test "a saved search's ids read the unread list once" do
    search = @user.saved_searches.create!(name: "Swift", query: "swift is:unread")
    swift_entries(1)

    reads = 0
    counter = ->(*, payload) { reads += 1 if payload[:sql].match?(/FROM "unreads"/) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      get "/v3/collections/search_#{search.id}/ids", headers: bearer
    end

    assert_equal 1, reads
  end

  test "a bulk update checks playlists with one query" do
    @user.podcast_subscriptions.create!(feed: @feed, status: :subscribed)
    playlist = @user.playlists.create!(title: "Commute")
    @entries.each_with_index { |entry, i| QueuedEntry.create!(user_id: @user.id, entry_id: entry.id, feed_id: @feed.id, order: i) }
    rows = @entries.map { {id: _1.id, playlist_id: playlist.id, playlist_id_updated_at: Time.now.iso8601} }

    reads = 0
    counter = ->(*, payload) { reads += 1 if payload[:sql].match?(/FROM "playlists"/) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      patch "/v3/collections/queue/entries", params: {entries: rows}.to_json, headers: json
    end

    assert_equal @entries.map(&:id), JSON.parse(response.body)["applied"]
    assert_equal 1, reads
  end

  private

  # Unread entries titled Swift, published oldest first, indexed for search.
  def swift_entries(count)
    entries = count.times.map do |i|
      @feed.entries.create!(title: "Swift #{i}", url: "https://example.com/swift/#{i}", public_id: SecureRandom.hex, entry_id: SecureRandom.hex, published: (count - i).days.ago)
    end
    entries.each { UnreadEntry.create_from_owners(@user, _1) }
    index_entries(entries)
    entries
  end

  def count_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end

  def bearer
    {"Authorization" => "Bearer #{@token.plaintext_token}"}
  end

  def json
    bearer.merge("Content-Type" => "application/json")
  end
end
