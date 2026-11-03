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
    @token = application.access_tokens.create!(resource_owner_id: @user.id, scopes: "read write account")
  end

  test "lists subscriptions ascending by id with feed and tag ids" do
    get "/v3/subscriptions", headers: bearer

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "list", body["object"]
    assert_nil body["page"]
    assert_nil body["meta"]
    assert_equal @subscriptions.map(&:id), body["data"].map { _1["id"] }
    assert_equal %w[object id created_at title custom_title feed_id tag_ids preferences], body["data"].first.keys
    assert_equal @feeds.map(&:id), body["data"].map { _1["feed_id"] }
    assert_equal Tag.where(name: %w[Apple News]).order(:name).pluck(:id), body["data"].first["tag_ids"]
    assert_equal [], body["data"].last["tag_ids"]
    assert_match(/\A"subscriptions:#{@user.id}:\h{32}"\z/, response.headers["ETag"])
  end

  test "expand=feed,tags embeds the feed and tag objects" do
    get "/v3/subscriptions", params: {expand: "feed,tags"}, headers: bearer

    body = JSON.parse(response.body)
    assert_equal %w[object id created_at title custom_title feed_id tag_ids preferences feed tags], body["data"].first.keys
    assert_equal @feeds.map(&:id), body["data"].map { _1["feed"]["id"] }
    assert_equal ["Apple", "News"], body["data"].first["tags"].map { _1["name"] }
    assert_equal [], body["data"].last["tags"]

    get "/v3/subscriptions", params: {expand: "feed,changes"}, headers: bearer
    assert_response :unprocessable_content
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

  test "a subscription with NULL preferences and no title still sends booleans and a title" do
    feed = @feeds.last
    feed.update_columns(title: nil, host: "example1.com")
    @subscriptions.last.update_columns(title: nil, muted: nil, media_only: nil, show_updates: nil)

    get "/v3/subscriptions", params: {expand: "feed"}, headers: bearer

    row = JSON.parse(response.body)["data"].last
    assert_equal({"muted" => false, "media_only" => false, "show_updates" => true}, row["preferences"])
    assert_equal "example1.com", row["title"]
    assert_nil row["custom_title"]
    assert_nil row["feed"]["title"]
  end

  test "a tag with no name sends an empty string in the embedded tags" do
    nameless = Tag.new.tap { _1.save!(validate: false) }
    @feeds.last.taggings.create!(user: @user, tag: nameless)

    get "/v3/subscriptions", params: {expand: "tags"}, headers: bearer

    assert_response :success
    tags = JSON.parse(response.body)["data"].last["tags"]
    assert_equal [{"object" => "tag", "id" => nameless.id, "name" => ""}], tags
  end

  test "leaves out the generated pages subscription" do
    pages_feed_with(1)

    get "/v3/subscriptions", headers: bearer

    assert_equal @subscriptions.map(&:id), JSON.parse(response.body)["data"].map { _1["id"] }
  end

  test "a subscription with no kind is listed" do
    @subscriptions.first.update_column(:kind, nil)

    get "/v3/subscriptions", headers: bearer
    assert_equal @subscriptions.map(&:id), JSON.parse(response.body)["data"].map { _1["id"] }

    get "/v3/subscriptions/#{@subscriptions.first.id}", headers: bearer
    assert_response :success
  end

  test "a generated subscription is not found" do
    feed, _ = pages_feed_with(1)
    id = @user.subscriptions.find_by!(feed: feed).id
    json = bearer.merge("Content-Type" => "application/json")

    get "/v3/subscriptions/#{id}", headers: bearer
    assert_response :not_found
    delete "/v3/subscriptions/#{id}", headers: bearer
    assert_response :not_found
    put "/v3/subscriptions/#{id}/tags", params: {tag_names: ["A"]}.to_json, headers: json
    assert_response :not_found
    patch "/v3/subscriptions/#{id}", params: {custom_title: "X"}.to_json, headers: json
    assert_response :not_found
  end

  private

  def pages_feed_with(count)
    feed = Feed.create!(feed_url: "https://pages.example/#{SecureRandom.hex}", title: "Pages", feed_type: :pages)
    @user.subscriptions.create!(feed: feed, kind: :generated)
    entries = count.times.map { |i| feed.entries.create!(title: "Page #{i}", url: "https://page.example/#{i}", public_id: SecureRandom.hex, entry_id: SecureRandom.hex, published: i.days.ago) }
    [feed, entries]
  end

  def bearer
    {"Authorization" => "Bearer #{@token.plaintext_token}"}
  end
end
