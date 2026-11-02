require "test_helper"
require "minitest/stub_any_instance"

class ApiV3StateTest < ActionDispatch::IntegrationTest
  setup do
    host! "api.example.com"
    @user = users(:new)
    @user.setting_on!(:api_v3)
    @feed = Feed.create!(feed_url: "https://example.com/feed", title: "Example")
    @user.subscriptions.create!(feed: @feed)
    @a, @b = 2.times.map { |i| @feed.entries.create!(title: "E#{i}", url: "https://example.com/#{i}", public_id: SecureRandom.hex, entry_id: SecureRandom.hex) }
    @other = Feed.create!(feed_url: "https://other.example/feed").entries.create!(title: "x", url: "https://other.example/1", public_id: SecureRandom.hex, entry_id: SecureRandom.hex)
    application = @user.oauth_applications.create!(name: "Reader", redirect_uri: "")
    @token = application.access_tokens.create!(resource_owner_id: @user.id, scopes: "read write account")
  end

  test "applies verbs and reports them by verb" do
    get "/v3/collections/unread/ids", headers: bearer
    etag = response.headers["ETag"]

    post "/v3/entries/state", params: {mark_read: [@a.id, @b.id], star: [@a.id]}.to_json, headers: bearer.merge("Content-Type" => "application/json")

    assert_response :success
    assert_equal({"applied" => {"mark_read" => [@a.id, @b.id], "star" => [@a.id]}, "skipped" => []}, JSON.parse(response.body))
    assert_equal [], UnreadEntry.where(user_id: @user.id).pluck(:entry_id)
    assert_equal [@a.id], StarredEntry.where(user_id: @user.id).pluck(:entry_id)

    get "/v3/collections/unread/ids", headers: bearer.merge("If-None-Match" => etag)
    assert_response :success
  end

  test "skips ids the user cannot touch and applies the rest" do
    post "/v3/entries/state", params: {mark_read: [@other.id, @a.id, 999_999_999]}.to_json, headers: bearer.merge("Content-Type" => "application/json")

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [@a.id], body["applied"]["mark_read"]
    assert_equal [{"id" => @other.id, "reason" => "not_subscribed"}, {"id" => 999_999_999, "reason" => "not_found"}], body["skipped"]
  end

  test "a scope on a verb that takes only ids is rejected" do
    post "/v3/entries/state", params: {star: {feed_ids: [@feed.id]}}.to_json, headers: json

    assert_response :unprocessable_content
    body = JSON.parse(response.body)
    assert_equal "validation_failed", body["code"]
    assert_equal({"pointer" => "/star", "code" => "invalid_value"}, body["errors"].first.slice("pointer", "code"))
  end

  test "mark_read takes a feed scope with an inclusive published bound" do
    @a.update_columns(published: 3.days.ago)
    @b.update_columns(published: 1.hour.ago)
    UnreadEntry.where(entry_id: [@a.id, @b.id]).each { _1.update_columns(published: Entry.find(_1.entry_id).published) }

    post "/v3/entries/state", params: {mark_read: {feed_ids: [@feed.id], published_before: @a.reload.published.utc.iso8601(6)}}.to_json, headers: json

    assert_response :success
    assert_equal({"applied" => {"mark_read" => {"count" => 1}}, "skipped" => []}, JSON.parse(response.body))
    assert_equal [@b.id], @user.unread_entries.pluck(:entry_id)
  end

  test "mark_read takes a tag scope with a received bound, and an empty scope marks everything" do
    @feed.tag("News", @user)
    tag = Tag.find_by!(name: "News")
    @user.unread_entries.where(entry_id: @b.id).update_all(entry_created_at: 1.minute.from_now)

    post "/v3/entries/state", params: {mark_read: {tag_ids: [tag.id], received_before: Time.now.utc.iso8601}}.to_json, headers: json
    assert_equal({"count" => 1}, JSON.parse(response.body)["applied"]["mark_read"])
    assert_equal [@b.id], @user.unread_entries.pluck(:entry_id)

    post "/v3/entries/state", params: {mark_read: {}}.to_json, headers: json
    assert_equal({"count" => 1}, JSON.parse(response.body)["applied"]["mark_read"])
    assert_equal [], @user.unread_entries.pluck(:entry_id)
  end

  test "mark_read takes a collection scope" do
    StarredEntry.create_from_owners(@user, @a)

    post "/v3/entries/state", params: {mark_read: {collection: "starred"}}.to_json, headers: json
    assert_equal({"count" => 1}, JSON.parse(response.body)["applied"]["mark_read"])
    assert_equal [@b.id], @user.unread_entries.pluck(:entry_id)
  end

  test "mark_read takes a saved search as a collection" do
    clear_search
    index_entries([@a, @b])
    search = @user.saved_searches.create!(name: "E0", query: "title:E0")

    post "/v3/entries/state", params: {mark_read: {collection: "search_#{search.id}"}}.to_json, headers: json
    assert_equal({"count" => 1}, JSON.parse(response.body)["applied"]["mark_read"])
    assert_equal [@b.id], @user.unread_entries.pluck(:entry_id)
  end

  test "a scope is validated key by key" do
    {{"collection" => "queue"} => "/mark_read/collection",
     {"collection" => "search_0"} => "/mark_read/collection",
     {"bogus" => 1} => "/mark_read/bogus",
     {"feed_ids" => ["1"]} => "/mark_read/feed_ids",
     {"published_before" => "yesterday"} => "/mark_read/published_before"}.each do |scope, pointer|
      post "/v3/entries/state", params: {mark_read: scope}.to_json, headers: json
      assert_response :unprocessable_content
      assert_equal pointer, JSON.parse(response.body)["errors"].first["pointer"], scope.inspect
    end
    assert_equal 2, @user.unread_entries.count
  end

  test "clear_updated takes ids or a scope" do
    [@a, @b].each { UpdatedEntry.new_from_owners(@user.id, _1).save! }

    post "/v3/entries/state", params: {clear_updated: [@a.id, @other.id]}.to_json, headers: json
    assert_response :success
    assert_equal({"applied" => {"clear_updated" => [@a.id]}, "skipped" => [{"id" => @other.id, "reason" => "not_subscribed"}]}, JSON.parse(response.body))
    assert_equal [@b.id], @user.updated_entries.pluck(:entry_id)

    post "/v3/entries/state", params: {clear_updated: {feed_ids: [@feed.id]}}.to_json, headers: json
    assert_equal({"count" => 1}, JSON.parse(response.body)["applied"]["clear_updated"])
    assert_equal [], @user.updated_entries.pluck(:entry_id)
    assert_equal 2, @user.unread_entries.count
  end

  test "rejects a non-JSON body" do
    post "/v3/entries/state", params: "mark_read[]=1", headers: bearer.merge("Content-Type" => "application/x-www-form-urlencoded")

    assert_response :unsupported_media_type
  end

  test "clear_updated clears a row whose entry is gone" do
    UpdatedEntry.new_from_owners(@user.id, @a).save!
    gone = @a.id
    Entry.where(id: gone).delete_all

    post "/v3/entries/state", params: {clear_updated: [gone]}.to_json, headers: json
    assert_response :success
    assert_equal({"clear_updated" => [gone]}, JSON.parse(response.body)["applied"])
    assert_equal [], @user.updated_entries.pluck(:entry_id)
  end

  test "a scope bound without a UTC offset is rejected" do
    post "/v3/entries/state", params: {mark_read: {published_before: "2026-11-02T10:00:00"}}.to_json, headers: json

    assert_response :unprocessable_content
    assert_equal "/mark_read/published_before", JSON.parse(response.body)["errors"].first["pointer"]
  end

  test "a saved-search scope whose query no longer parses is query_invalid" do
    search = @user.saved_searches.create!(name: "Broken", query: "E0")
    search.update_column(:query, "title:(")

    post "/v3/entries/state", params: {mark_read: {collection: "search_#{search.id}"}}.to_json, headers: json

    assert_response :unprocessable_content
    assert_equal "query_invalid", JSON.parse(response.body)["code"]
    assert_equal 2, @user.unread_entries.count
  end

  test "a saved-search sweep over many matches deletes only the user's unread rows" do
    search = @user.saved_searches.create!(name: "E", query: "E0")
    matches = (1..25_000).to_a - [@a.id, @b.id] + [@a.id, @b.id]

    Search::Connection.stub_any_instance(:all_matches, matches) do
      post "/v3/entries/state", params: {mark_read: {collection: "search_#{search.id}"}}.to_json, headers: json
    end

    assert_equal({"count" => 2}, JSON.parse(response.body)["applied"]["mark_read"])
    assert_equal 0, @user.unread_entries.count
  end

  private

  def bearer
    {"Authorization" => "Bearer #{@token.plaintext_token}"}
  end

  def json
    bearer.merge("Content-Type" => "application/json")
  end
end
