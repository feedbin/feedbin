require "test_helper"

class ApiV3EntriesTest < ActionDispatch::IntegrationTest
  setup do
    host! "api.example.com"
    @user = users(:new)
    @user.setting_on!(:api_v3)
    @feed = Feed.create!(feed_url: "https://example.com/feed", host: "example.com", title: "Example", site_url: "https://example.com")
    @user.subscriptions.create!(feed: @feed)
    @entries = 3.times.map do |index|
      @feed.entries.create!(
        title: "Entry #{index}",
        url: "https://example.com/#{index}",
        content: "<p>Words in entry #{index}</p>",
        public_id: SecureRandom.hex,
        entry_id: SecureRandom.hex,
        published: (10 - index).days.ago,
        created_at: (3 - index).hours.ago
      )
    end
    application = @user.oauth_applications.create!(name: "Reader", redirect_uri: "")
    @token = application.access_tokens.create!(resource_owner_id: @user.id, scopes: "full")
  end

  test "lists the timeline newest received first" do
    get "/v3/entries", headers: bearer

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "list", body["object"]
    assert_equal @entries.reverse.map(&:id), body["data"].map { _1["id"] }
    assert_nil body["page"]["next_cursor"]
    assert_nil body["page"]["next_url"]
  end

  test "serializes every field of an entry" do
    entry = @entries.last
    entry.update!(categories: ["Technology"], data: {"enclosure_url" => "https://example.com/412.mp3", "enclosure_type" => "audio/mpeg", "enclosure_length" => "43018332", "itunes_duration" => "1:46:52"}, chapters: [{"start_time" => "812.5", "tags" => {"title" => "Filesystems"}}])

    get "/v3/entries", params: {ids: entry.id.to_s}, headers: bearer

    json = JSON.parse(response.body)["data"].first
    assert_equal %w[object id feed_id kind title author summary url hostname published_at received_at revision edited_at reading images link_preview attachments origin categories urls content original diff extracted], json.keys
    assert_equal "podcast", json["kind"]
    assert_equal "Entry 2", json["title"]
    assert_equal "example.com", json["hostname"]
    assert_equal entry.published.utc.iso8601, json["published_at"]
    assert_equal 1, json["revision"]
    assert_equal({"word_count" => 4, "minutes" => 1}, json["reading"])
    assert_equal({"preview" => nil, "icon" => nil}, json["images"])
    assert_equal ["Technology"], json["categories"]
    assert_equal "http://example.com/entries/#{entry.id}", json["urls"]["app"]
    assert_includes json["content"]["html"], "Words in entry 2"
    assert_nil json["original"]
    assert_equal [], json["extracted"]

    attachment = json["attachments"].first
    assert_equal({"url" => "https://example.com/412.mp3", "mime_type" => "audio/mpeg", "kind" => "audio", "title" => nil, "size_in_bytes" => 43018332, "duration_in_seconds" => 6412, "chapters" => [{"start_in_seconds" => 812, "title" => "Filesystems"}]}, attachment)
  end

  test "pages with a cursor" do
    get "/v3/entries", params: {limit: 2}, headers: bearer
    first = JSON.parse(response.body)
    assert_equal @entries.reverse.first(2).map(&:id), first["data"].map { _1["id"] }
    assert first["page"]["next_cursor"].present?
    assert_includes first["page"]["next_url"], "limit=2"

    get first["page"]["next_url"].delete_prefix("http://api.example.com"), headers: bearer
    second = JSON.parse(response.body)
    assert_equal [@entries.first.id], second["data"].map { _1["id"] }
    assert_nil second["page"]["next_cursor"]
  end

  test "keeps pages stable when new entries arrive" do
    get "/v3/entries", params: {limit: 2}, headers: bearer
    cursor = JSON.parse(response.body)["page"]["next_cursor"]

    @feed.entries.create!(title: "New", url: "https://example.com/new", public_id: SecureRandom.hex, entry_id: SecureRandom.hex)

    get "/v3/entries", params: {limit: 2, cursor: cursor}, headers: bearer
    assert_equal [@entries.first.id], JSON.parse(response.body)["data"].map { _1["id"] }
  end

  test "sorts by published date" do
    get "/v3/entries", params: {sort: "published_desc"}, headers: bearer

    assert_equal @entries.reverse.map(&:id), JSON.parse(response.body)["data"].map { _1["id"] }
  end

  test "rejects a cursor from another sort" do
    get "/v3/entries", params: {limit: 1}, headers: bearer
    cursor = JSON.parse(response.body)["page"]["next_cursor"]

    get "/v3/entries", params: {limit: 1, sort: "published_desc", cursor: cursor}, headers: bearer

    assert_response :bad_request
    assert_equal "cursor_invalid", JSON.parse(response.body)["code"]
  end

  test "filters by read and starred" do
    @user.unread_entries.delete_all
    UnreadEntry.create_from_owners(@user, @entries.first)
    StarredEntry.create_from_owners(@user, @entries.last)

    get "/v3/entries", params: {read: "false"}, headers: bearer
    assert_equal [@entries.first.id], JSON.parse(response.body)["data"].map { _1["id"] }

    get "/v3/entries", params: {starred: "true"}, headers: bearer
    assert_equal [@entries.last.id], JSON.parse(response.body)["data"].map { _1["id"] }

    get "/v3/entries", params: {read: "true", starred: "false"}, headers: bearer
    assert_equal [@entries.second.id], JSON.parse(response.body)["data"].map { _1["id"] }
  end

  test "filters by received_after" do
    get "/v3/entries", params: {received_after: @entries.second.created_at.iso8601(6)}, headers: bearer

    assert_equal [@entries.last.id], JSON.parse(response.body)["data"].map { _1["id"] }
  end

  test "lists edits in the order they happened" do
    @entries.first.update!(revision: 2, edited_at: 1.minute.ago)
    @entries.last.update!(revision: 3, edited_at: 5.minutes.ago)

    get "/v3/entries", params: {edited_after: 1.hour.ago.iso8601}, headers: bearer

    data = JSON.parse(response.body)["data"]
    assert_equal [@entries.last.id, @entries.first.id], data.map { _1["id"] }
    assert_equal [3, 2], data.map { _1["revision"] }
  end

  test "counts the whole list with total=true" do
    get "/v3/entries", params: {limit: 1, total: "true"}, headers: bearer

    assert_equal 3, JSON.parse(response.body)["meta"]["total"]
  end

  test "returns entries by id in the order given, with the rest missing" do
    other_feed = Feed.create!(feed_url: "https://other.example/feed", host: "other.example", title: "Other")
    unreadable = other_feed.entries.create!(title: "Hidden", url: "https://other.example/1", public_id: SecureRandom.hex, entry_id: SecureRandom.hex)
    ids = [@entries.first.id, unreadable.id, 0x7fff_ffff, @entries.last.id]

    get "/v3/entries", params: {ids: ids.join(",")}, headers: bearer

    body = JSON.parse(response.body)
    assert_equal [@entries.first.id, @entries.last.id], body["data"].map { _1["id"] }
    assert_equal [unreadable.id, 0x7fff_ffff], body["meta"]["missing"]
    refute body.key?("page")
  end

  test "a starred entry from an unsubscribed feed is readable by id" do
    other_feed = Feed.create!(feed_url: "https://other.example/feed", host: "other.example", title: "Other")
    starred = other_feed.entries.create!(title: "Kept", url: "https://other.example/1", public_id: SecureRandom.hex, entry_id: SecureRandom.hex)
    StarredEntry.create_from_owners(@user, starred)

    get "/v3/entries", params: {ids: starred.id.to_s}, headers: bearer

    assert_equal [starred.id], JSON.parse(response.body)["data"].map { _1["id"] }
  end

  test "rejects invalid parameters" do
    {
      {ids: "1,abc"} => "ids",
      {ids: (1..501).to_a.join(",")} => "ids",
      {read: "yes"} => "read",
      {sort: "oldest"} => "sort",
      {received_after: "yesterday"} => "received_after",
      {limit: "0"} => "limit"
    }.each do |params, pointer|
      get "/v3/entries", params: params, headers: bearer

      assert_response :unprocessable_content, params.inspect
      body = JSON.parse(response.body)
      assert_equal "validation_failed", body["code"]
      assert_equal pointer, body["errors"].first["pointer"]
    end
  end

  private

  def bearer
    {"Authorization" => "Bearer #{@token.plaintext_token}"}
  end
end
