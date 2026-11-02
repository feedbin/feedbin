require "test_helper"

class ApiV3ActionsTest < ActionDispatch::IntegrationTest
  setup do
    host! "api.example.com"
    @user = users(:new)
    @user.setting_on!(:api_v3)
    clear_search
    @feed = Feed.create!(feed_url: "https://example.com/feed", host: "example.com", title: "Example")
    @user.subscriptions.create!(feed: @feed)
    @feed.tag("Apple", @user)
    @tag = Tag.find_by!(name: "Apple")
    @entries = 2.times.map { |i| @feed.entries.create!(title: "Swift #{i}", content: "<p>Swift</p>", url: "https://example.com/#{i}", public_id: SecureRandom.hex, entry_id: SecureRandom.hex, published: (2 - i).days.ago) }
    index_entries(@entries)
    application = @user.oauth_applications.create!(name: "Reader", redirect_uri: "")
    @token = application.access_tokens.create!(resource_owner_id: @user.id, scopes: "read write account")
  end

  test "creates, lists, updates, previews and deletes an action" do
    post "/v3/actions", params: {title: "Star Swift", kind: "standard", query: "title:swift", tag_ids: [@tag.id, 0], actions: ["star"]}.to_json, headers: json
    assert_response :created
    body = JSON.parse(response.body)
    assert_equal %w[object id title kind query feed_ids tag_ids actions status error_hint], body.keys
    assert_equal ["Star Swift", "standard", "title:swift", [], [@tag.id], ["star"], "active", nil], body.values_at("title", "kind", "query", "feed_ids", "tag_ids", "actions", "status", "error_hint")

    get "/v3/actions", headers: bearer
    assert_response :success
    assert_equal [body["id"]], JSON.parse(response.body)["data"].map { _1["id"] }
    assert_nil JSON.parse(response.body)["meta"]
    etag = response.headers["ETag"]
    get "/v3/actions", headers: bearer.merge("If-None-Match" => etag)
    assert_response :not_modified

    patch "/v3/actions/#{body["id"]}", params: {actions: ["star", "mark_read"], feed_ids: [@feed.id, 0]}.to_json, headers: json
    assert_response :success
    assert_equal [["star", "mark_read"], [@feed.id]], JSON.parse(response.body).values_at("actions", "feed_ids")

    get "/v3/actions/#{body["id"]}/entries", headers: bearer
    assert_response :success
    preview = JSON.parse(response.body)
    assert_equal @entries.reverse.map(&:id), preview["data"].map { _1["id"] }
    assert_equal 50, preview["page"]["limit"]

    delete "/v3/actions/#{body["id"]}", headers: bearer
    assert_response :no_content
    delete "/v3/actions/#{body["id"]}", headers: bearer
    assert_response :not_found
  end

  test "an empty scope applies to every feed and validates the body" do
    post "/v3/actions", params: {title: "Everything", kind: "standard", query: "", actions: ["mark_read"]}.to_json, headers: json
    assert_response :created
    assert Action.find(JSON.parse(response.body)["id"]).all_feeds

    post "/v3/actions", params: {title: "", kind: "standard"}.to_json, headers: json
    assert_response :unprocessable_content
    assert_equal "/title", JSON.parse(response.body)["errors"].first["pointer"]

    post "/v3/actions", params: {title: "Mute", kind: "mute"}.to_json, headers: json
    assert_response :unprocessable_content
    assert_equal "/query", JSON.parse(response.body)["errors"].first["pointer"]

    post "/v3/actions", params: {title: "Bad", kind: "standard", query: "title:("}.to_json, headers: json
    assert_response :unprocessable_content
    assert_equal "query_invalid", JSON.parse(response.body)["code"]

    post "/v3/actions", params: {title: "Odd", kind: "sideways"}.to_json, headers: json
    assert_response :unprocessable_content
    assert_equal "/kind", JSON.parse(response.body)["errors"].first["pointer"]
  end

  test "mute and notifier set their own actions, and there is one notifier" do
    post "/v3/actions", params: {title: "Mute", kind: "mute", query: "swift", actions: ["star"]}.to_json, headers: json
    assert_equal ["mark_read"], JSON.parse(response.body)["actions"]

    post "/v3/actions", params: {title: "Notify", kind: "notifier", actions: ["star"]}.to_json, headers: json
    assert_response :created
    assert_equal ["send_ios_notification"], JSON.parse(response.body)["actions"]

    post "/v3/actions", params: {title: "Notify again", kind: "notifier"}.to_json, headers: json
    assert_response :unprocessable_content
    assert_equal "/kind", JSON.parse(response.body)["errors"].first["pointer"]
  end

  test "a scope of only foreign ids does not widen to every feed" do
    post "/v3/actions", params: {title: "Nothing", kind: "standard", feed_ids: [0]}.to_json, headers: json
    assert_response :unprocessable_content
    assert_equal "/feed_ids", JSON.parse(response.body)["errors"].first["pointer"]
  end

  test "a rule whose scope lost every feed previews nothing" do
    post "/v3/actions", params: {title: "Star Swift", kind: "standard", query: "title:swift", tag_ids: [@tag.id], actions: ["star"]}.to_json, headers: json
    action = Action.find(JSON.parse(response.body)["id"])
    action.update_columns(computed_feed_ids: [])

    get "/v3/actions/#{action.id}/entries", headers: bearer
    assert_response :success
    assert_equal [], JSON.parse(response.body)["data"]
  end

  private

  def bearer
    {"Authorization" => "Bearer #{@token.plaintext_token}"}
  end

  def json
    bearer.merge("Content-Type" => "application/json")
  end
end
