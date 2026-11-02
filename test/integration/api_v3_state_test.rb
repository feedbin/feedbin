require "test_helper"

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
    @token = application.access_tokens.create!(resource_owner_id: @user.id, scopes: "full")
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

  test "rejects a scope object with a pointer to the verb" do
    post "/v3/entries/state", params: {mark_read: {feed_ids: [@feed.id]}}.to_json, headers: bearer.merge("Content-Type" => "application/json")

    assert_response :unprocessable_content
    body = JSON.parse(response.body)
    assert_equal "validation_failed", body["code"]
    assert_equal({"pointer" => "/mark_read", "code" => "invalid_value"}, body["errors"].first.slice("pointer", "code"))
  end

  test "rejects a non-JSON body" do
    post "/v3/entries/state", params: "mark_read[]=1", headers: bearer.merge("Content-Type" => "application/x-www-form-urlencoded")

    assert_response :unsupported_media_type
  end

  private

  def bearer
    {"Authorization" => "Bearer #{@token.plaintext_token}"}
  end
end
