require "test_helper"

class ApiV3SavedSearchesTest < ActionDispatch::IntegrationTest
  setup do
    host! "api.example.com"
    @user = users(:new)
    @user.setting_on!(:api_v3)
    clear_search
    # Validation only parses the text when the scope can match something.
    @user.subscriptions.create!(feed: Feed.create!(feed_url: "https://example.com/feed", title: "Example"))
    @search = @user.saved_searches.create!(name: "Swift", query: "swift")
    application = @user.oauth_applications.create!(name: "Reader", redirect_uri: "")
    @token = application.access_tokens.create!(resource_owner_id: @user.id, scopes: "full")
  end

  test "lists saved searches by name with an etag" do
    @user.saved_searches.create!(name: "apple", query: "apple")
    get "/v3/saved_searches", headers: bearer

    assert_response :success
    body = JSON.parse(response.body)
    assert_nil body["meta"]
    assert_equal ["apple", "Swift"], body["data"].map { _1["title"] }
    assert_equal({"object" => "saved_search", "id" => @search.id, "title" => "Swift", "query" => "swift", "collection_id" => "search_#{@search.id}", "created_at" => @search.created_at.utc.iso8601, "updated_at" => @search.updated_at.utc.iso8601}, body["data"].last)
    etag = response.headers["ETag"]

    get "/v3/saved_searches", headers: bearer.merge("If-None-Match" => etag)
    assert_response :not_modified
  end

  test "creates, updates and deletes a saved search" do
    post "/v3/saved_searches", params: {title: "Rust", query: "rust"}.to_json, headers: json
    assert_response :created
    body = JSON.parse(response.body)
    assert_equal ["Rust", "rust", "search_#{body["id"]}"], body.values_at("title", "query", "collection_id")

    patch "/v3/saved_searches/#{body["id"]}", params: {title: "Rust lang"}.to_json, headers: json
    assert_response :success
    assert_equal ["Rust lang", "rust"], JSON.parse(response.body).values_at("title", "query")

    delete "/v3/saved_searches/#{body["id"]}", headers: bearer
    assert_response :no_content
    delete "/v3/saved_searches/#{body["id"]}", headers: bearer
    assert_response :not_found
  end

  test "rejects a blank title and a query that does not parse" do
    post "/v3/saved_searches", params: {title: " ", query: "x"}.to_json, headers: json
    assert_response :unprocessable_content
    assert_equal ["validation_failed", "/title"], [JSON.parse(response.body)["code"], JSON.parse(response.body)["errors"].first["pointer"]]

    post "/v3/saved_searches", params: {title: "Bad", query: "title:("}.to_json, headers: json
    assert_response :unprocessable_content
    assert_equal "query_invalid", JSON.parse(response.body)["code"]

    patch "/v3/saved_searches/#{@search.id}", params: {query: "swift AND"}.to_json, headers: json
    assert_response :unprocessable_content
    assert_equal "query_invalid", JSON.parse(response.body)["code"]
  end

  test "another user's saved search is not found" do
    other = users(:ben).saved_searches.create!(name: "Theirs", query: "x")
    patch "/v3/saved_searches/#{other.id}", params: {title: "Mine"}.to_json, headers: json
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
