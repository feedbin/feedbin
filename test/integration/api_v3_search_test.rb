require "test_helper"

class ApiV3SearchTest < ActionDispatch::IntegrationTest
  setup do
    host! "api.example.com"
    @user = users(:new)
    @user.setting_on!(:api_v3)
    @feed = Feed.create!(feed_url: "https://example.com/feed", host: "example.com", title: "Example")
    @user.subscriptions.create!(feed: @feed)
    @entries = 3.times.map do |i|
      @feed.entries.create!(title: "Swift tip #{i}", content: "<p>About Swift #{i}</p>", url: "https://example.com/#{i}", public_id: SecureRandom.hex, entry_id: SecureRandom.hex, published: (3 - i).days.ago)
    end
    @unrelated = @feed.entries.create!(title: "Gardening", content: "<p>Tomatoes</p>", url: "https://example.com/g", public_id: SecureRandom.hex, entry_id: SecureRandom.hex, published: 10.days.ago)
    clear_search
    index_entries(@entries + [@unrelated])
    application = @user.oauth_applications.create!(name: "Reader", redirect_uri: "")
    @token = application.access_tokens.create!(resource_owner_id: @user.id, scopes: "read write account")
  end

  test "searches newest published first with a cursor and the query it ran" do
    get "/v3/search", params: {query: "swift", limit: 2, total: "true"}, headers: bearer

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @entries.reverse.first(2).map(&:id), body["data"].map { _1["id"] }
    assert_equal 2, body["page"]["limit"]
    assert_equal({"total" => 3, "query" => "swift"}, body["meta"].slice("total", "query"))
    assert body["meta"]["as_of"].present?

    get body["page"]["next_url"].delete_prefix("http://api.example.com"), headers: bearer
    second = JSON.parse(response.body)
    assert_equal [@entries.first.id], second["data"].map { _1["id"] }
    assert_nil second["page"]["next_url"]
  end

  test "folds structured parameters into the query" do
    StarredEntry.create_from_owners(@user, @entries.first)
    @feed.tag("Apple", @user)
    tag = Tag.find_by!(name: "Apple")

    get "/v3/search", params: {query: "swift", starred: "true", feed_ids: @feed.id.to_s, published_after: 4.days.ago.iso8601}, headers: bearer
    body = JSON.parse(response.body)
    assert_equal [@entries.first.id], body["data"].map { _1["id"] }
    assert_includes body["meta"]["query"], "is:starred"
    assert_includes body["meta"]["query"], "feed_id:(#{@feed.id})"

    get "/v3/search", params: {query: "swift", tag_ids: tag.id.to_s}, headers: bearer
    assert_equal 3, JSON.parse(response.body)["data"].size
    assert_match(/feed_id:\(?#{@feed.id}\)?/, JSON.parse(response.body)["meta"]["query"])
    refute_includes JSON.parse(response.body)["meta"]["query"], "tag_id"
  end

  test "an OR in the query does not loosen the structured parameters" do
    other = Feed.create!(feed_url: "https://other.example/feed", host: "other.example", title: "Other")
    @user.subscriptions.create!(feed: other)
    elsewhere = other.entries.create!(title: "Swift elsewhere", content: "<p>Swift</p>", url: "https://other.example/1", public_id: SecureRandom.hex, entry_id: SecureRandom.hex, published: 1.day.ago)
    index_entries([elsewhere])

    get "/v3/search", params: {query: "swift OR tomatoes", feed_ids: other.id.to_s}, headers: bearer
    assert_equal [elsewhere.id], JSON.parse(response.body)["data"].map { _1["id"] }

    get "/v3/search", params: {query: "gardening OR tomatoes", published_after: 4.days.ago.iso8601}, headers: bearer
    assert_equal [], JSON.parse(response.body)["data"]
  end

  test "rejects a query that does not parse and a missing query" do
    get "/v3/search", params: {query: "title:("}, headers: bearer
    assert_response :unprocessable_content
    assert_equal "query_invalid", JSON.parse(response.body)["code"]

    get "/v3/search", headers: bearer
    assert_response :unprocessable_content
    assert_equal "validation_failed", JSON.parse(response.body)["code"]
  end

  test "a saved search's collection entries are its search" do
    search = @user.saved_searches.create!(name: "Swift", query: "swift")

    get "/v3/collections/search_#{search.id}/entries", params: {limit: 2}, headers: bearer
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @entries.reverse.first(2).map(&:id), body["data"].map { _1["id"] }
    refute body["data"].first.key?("membership")
  end

  private

  def bearer
    {"Authorization" => "Bearer #{@token.plaintext_token}"}
  end
end
