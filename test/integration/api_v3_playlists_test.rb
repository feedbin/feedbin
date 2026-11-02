require "test_helper"

class ApiV3PlaylistsTest < ActionDispatch::IntegrationTest
  setup do
    host! "api.example.com"
    @user = users(:new)
    @user.setting_on!(:api_v3)
    application = @user.oauth_applications.create!(name: "Reader", redirect_uri: "")
    @token = application.access_tokens.create!(resource_owner_id: @user.id, scopes: "read write account")
  end

  test "creates, lists, finds by title, updates with timestamps and deletes" do
    post "/v3/playlists", params: {title: "Commute", sort: "published_desc"}.to_json, headers: json
    assert_response :created
    body = JSON.parse(response.body)
    assert_equal %w[object id title sort created_at updated_at], body.keys
    assert_equal ["playlist", "Commute", "published_desc"], body.values_at("object", "title", "sort")

    post "/v3/playlists", params: {title: "Commute"}.to_json, headers: json
    assert_response :success
    assert_equal body["id"], JSON.parse(response.body)["id"]

    get "/v3/playlists", headers: bearer
    assert_equal [body["id"]], JSON.parse(response.body)["data"].map { _1["id"] }
    assert_nil JSON.parse(response.body)["meta"]
    etag = response.headers["ETag"]
    get "/v3/playlists", headers: bearer.merge("If-None-Match" => etag)
    assert_response :not_modified

    playlist = Playlist.find(body["id"])
    stored_at = playlist.title_updated_at
    patch "/v3/playlists/#{body["id"]}", params: {title: "Old name", title_updated_at: (stored_at - 1.minute).iso8601, sort: "manual", sort_updated_at: Time.now.iso8601}.to_json, headers: json
    assert_response :success
    assert_equal ["Commute", "manual"], JSON.parse(response.body).values_at("title", "sort")

    patch "/v3/playlists/#{body["id"]}", params: {title: "No stamp"}.to_json, headers: json
    assert_response :unprocessable_content
    assert_equal "/title_updated_at", JSON.parse(response.body)["errors"].first["pointer"]

    QueuedEntry.create!(user_id: @user.id, entry_id: Feed.create!(feed_url: "https://x.example/f").entries.create!(title: "e", url: "https://x.example/1", public_id: SecureRandom.hex, entry_id: SecureRandom.hex).id, feed_id: Feed.last.id, playlist_id: body["id"])
    delete "/v3/playlists/#{body["id"]}", headers: bearer
    assert_response :no_content
    assert_equal [nil], @user.queued_entries.pluck(:playlist_id)
    delete "/v3/playlists/#{body["id"]}", headers: bearer
    assert_response :not_found
  end

  private

  def bearer
    {"Authorization" => "Bearer #{@token.plaintext_token}"}
  end

  def json
    bearer.merge("Content-Type" => "application/json")
  end
end
