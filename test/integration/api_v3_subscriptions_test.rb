require "test_helper"

class ApiV3SubscriptionsTest < ActionDispatch::IntegrationTest
  setup do
    host! "api.example.com"
    @user = users(:new)
    @user.setting_on!(:api_v3)
    @feeds = 2.times.map { |i| Feed.create!(feed_url: "https://example#{i}.com/feed", host: "example#{i}.com", title: "Example #{i}") }
    @subscriptions = @feeds.map { @user.subscriptions.create!(feed: _1) }
    @feeds.first.tag("Apple, News", @user)
    application = @user.oauth_applications.create!(name: "Reader", redirect_uri: "")
    @token = application.access_tokens.create!(resource_owner_id: @user.id, scopes: "full")
  end

  test "lists subscriptions ascending by id with feeds and tags embedded" do
    get "/v3/subscriptions", headers: bearer

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "list", body["object"]
    assert_nil body["page"]
    assert_equal @subscriptions.map(&:id), body["data"].map { _1["id"] }
    assert_equal @feeds.map(&:id), body["data"].map { _1["feed"]["id"] }
    assert_equal ["Apple", "News"], body["data"].first["tags"].map { _1["name"] }
    assert_equal [], body["data"].last["tags"]
    assert_equal %("subscriptions:#{@user.id}:#{SyncVersion.for(@user)["subscriptions"]}"), response.headers["ETag"]
  end

  test "returns 304 until a subscription changes" do
    get "/v3/subscriptions", headers: bearer
    etag = response.headers["ETag"]

    get "/v3/subscriptions", headers: bearer.merge("If-None-Match" => etag)
    assert_response :not_modified

    @subscriptions.first.update!(title: "Renamed")

    get "/v3/subscriptions", headers: bearer.merge("If-None-Match" => etag)
    assert_response :success
    assert_equal "Renamed", JSON.parse(response.body)["data"].first["title"]
  end

  test "leaves out other users' subscriptions" do
    users(:ben).subscriptions.create!(feed: @feeds.first)

    get "/v3/subscriptions", headers: bearer

    assert_equal @subscriptions.map(&:id), JSON.parse(response.body)["data"].map { _1["id"] }
  end

  private

  def bearer
    {"Authorization" => "Bearer #{@token.plaintext_token}"}
  end
end
