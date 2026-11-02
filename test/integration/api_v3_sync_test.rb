require "test_helper"

class ApiV3SyncTest < ActionDispatch::IntegrationTest
  setup do
    host! "api.example.com"
    @user = users(:new)
    @user.setting_on!(:api_v3)
    @feed = Feed.create!(feed_url: "https://example.com/feed", title: "Example")
    @user.subscriptions.create!(feed: @feed)
    @entries = 2.times.map do |i|
      @feed.entries.create!(title: "E#{i}", url: "https://example.com/#{i}", public_id: SecureRandom.hex, entry_id: SecureRandom.hex, created_at: (2 - i).hours.ago)
    end
    application = @user.oauth_applications.create!(name: "Reader", redirect_uri: "")
    @token = application.access_tokens.create!(resource_owner_id: @user.id, scopes: "full")
  end

  test "bundles every list's etag and a cursor at the newest entry" do
    get "/v3/sync", headers: bearer

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal %w[object as_of entries_cursor etags poll_interval_in_seconds], body.keys
    assert_equal "sync", body["object"]
    assert_equal 900, body["poll_interval_in_seconds"]
    assert_equal %w[unread starred subscriptions], body["etags"].keys

    %w[unread starred].each do |list|
      get "/v3/collections/#{list}/ids", headers: bearer
      assert_equal response.headers["ETag"], body["etags"][list]
    end
    get "/v3/subscriptions", headers: bearer
    assert_equal response.headers["ETag"], body["etags"]["subscriptions"]

    cursor = Api::V3::Cursor.decode(body["entries_cursor"])
    assert_equal "received_asc", cursor["sort"]
    assert_equal @entries.last.id, cursor["id"]

    get "/v3/entries", params: {sort: "received_asc", cursor: body["entries_cursor"]}, headers: bearer
    assert_equal [], JSON.parse(response.body)["data"]
  end

  test "pages arrivals from the saved cursor" do
    get "/v3/sync", headers: bearer
    saved = JSON.parse(response.body)["entries_cursor"]

    arrival = @feed.entries.create!(title: "New", url: "https://example.com/new", public_id: SecureRandom.hex, entry_id: SecureRandom.hex)

    get "/v3/entries", params: {sort: "received_asc", cursor: saved}, headers: bearer
    assert_equal [arrival.id], JSON.parse(response.body)["data"].map { _1["id"] }
  end

  test "a user with nothing gets a null cursor and version-zero etags" do
    @user.subscriptions.destroy_all

    get "/v3/sync", headers: bearer

    body = JSON.parse(response.body)
    assert_nil body["entries_cursor"]
    assert_equal %("unread:#{SyncVersion.for(@user)["unread"]}"), body["etags"]["unread"]
  end

  test "returns 304 until a list or the newest entry changes" do
    get "/v3/sync", headers: bearer
    etag = response.headers["ETag"]
    assert etag.present?

    get "/v3/sync", headers: bearer.merge("If-None-Match" => etag)
    assert_response :not_modified

    StarredEntry.create_from_owners(@user, @entries.first)
    get "/v3/sync", headers: bearer.merge("If-None-Match" => etag)
    assert_response :success
    etag = response.headers["ETag"]

    @feed.entries.create!(title: "New", url: "https://example.com/new", public_id: SecureRandom.hex, entry_id: SecureRandom.hex)
    get "/v3/sync", headers: bearer.merge("If-None-Match" => etag)
    assert_response :success
    refute_equal etag, response.headers["ETag"]
  end

  private

  def bearer
    {"Authorization" => "Bearer #{@token.plaintext_token}"}
  end
end
