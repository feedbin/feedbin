require "test_helper"

class ApiV3CollectionsTest < ActionDispatch::IntegrationTest
  setup do
    host! "api.example.com"
    @user = users(:new)
    @user.setting_on!(:api_v3)
    @feed = Feed.create!(feed_url: "https://example.com/feed", title: "Example")
    @user.subscriptions.create!(feed: @feed)
    @entries = 3.times.map do |index|
      @feed.entries.create!(title: "Entry #{index}", url: "https://example.com/#{index}", public_id: SecureRandom.hex, entry_id: SecureRandom.hex)
    end
    application = @user.oauth_applications.create!(name: "Reader", redirect_uri: "")
    @token = application.access_tokens.create!(resource_owner_id: @user.id, scopes: "full")
  end

  test "lists unread ids ascending with an etag" do
    @user.unread_entries.delete_all
    @entries.each { UnreadEntry.create_from_owners(@user, _1) }

    get "/v3/collections/unread/ids", headers: bearer

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "list", body["object"]
    assert_equal @entries.map(&:id).sort, body["data"]
    assert_nil body["page"]
    assert body["meta"]["as_of"].present?
    assert_equal %("unread:#{@user.id}:#{SyncVersion.for(@user)["unread"]}"), response.headers["ETag"]
  end

  test "another account's etag at the same version is not a match" do
    get "/v3/collections/unread/ids", headers: bearer
    etag = response.headers["ETag"]
    other = users(:ben)
    other.setting_on!(:api_v3)
    other_token = other.oauth_applications.create!(name: "Reader", redirect_uri: "").access_tokens.create!(resource_owner_id: other.id, scopes: "full")
    # This account's tag at the other account's version: what a URL-keyed
    # cache would send after an account switch if the tag held no account.
    etag_at_other_version = etag.sub(/:\d+"\z/, %(:#{SyncVersion.for(other)["unread"]}"))

    get "/v3/collections/unread/ids", headers: {"Authorization" => "Bearer #{other_token.plaintext_token}", "If-None-Match" => etag_at_other_version}

    assert_response :success
    refute_equal etag, response.headers["ETag"]
  end

  test "leaves a starred row with no entry out of the list" do
    StarredEntry.create_from_owners(@user, @entries.first)
    StarredEntry.insert_all([{user_id: @user.id, feed_id: @feed.id, entry_id: nil, published: Time.now, created_at: Time.now, updated_at: Time.now}])

    get "/v3/collections/starred/ids", headers: bearer

    assert_equal [@entries.first.id], JSON.parse(response.body)["data"]
  end

  test "returns 304 for a matching etag, weak or strong, and 200 after a change" do
    get "/v3/collections/starred/ids", headers: bearer
    etag = response.headers["ETag"]

    get "/v3/collections/starred/ids", headers: bearer.merge("If-None-Match" => etag)
    assert_response :not_modified
    assert_empty response.body

    get "/v3/collections/starred/ids", headers: bearer.merge("If-None-Match" => "W/#{etag}")
    assert_response :not_modified

    StarredEntry.create_from_owners(@user, @entries.first)

    get "/v3/collections/starred/ids", headers: bearer.merge("If-None-Match" => etag)
    assert_response :success
    refute_equal etag, response.headers["ETag"]
    assert_equal [@entries.first.id], JSON.parse(response.body)["data"]
  end

  test "unknown collections are not found" do
    get "/v3/collections/queue/ids", headers: bearer

    assert_response :not_found
    assert_equal "not_found", JSON.parse(response.body)["code"]
  end

  private

  def bearer
    {"Authorization" => "Bearer #{@token.plaintext_token}"}
  end
end
