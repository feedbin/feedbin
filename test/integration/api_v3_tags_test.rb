require "test_helper"

class ApiV3TagsTest < ActionDispatch::IntegrationTest
  setup do
    host! "api.example.com"
    @user = users(:new)
    @user.setting_on!(:api_v3)
    @feeds = 2.times.map { |i| Feed.create!(feed_url: "https://example#{i}.com/feed", title: "Example #{i}") }
    @subscriptions = @feeds.map { @user.subscriptions.create!(feed: _1) }
    @feeds.first.tag("Apple, News", @user)
    @feeds.last.tag("News", @user)
    @apple = Tag.find_by!(name: "Apple")
    @news = Tag.find_by!(name: "News")
    application = @user.oauth_applications.create!(name: "Reader", redirect_uri: "")
    @token = application.access_tokens.create!(resource_owner_id: @user.id, scopes: "full")
  end

  test "lists the user's tags by name with their subscription ids and an etag" do
    get "/v3/tags", headers: bearer

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "list", body["object"]
    assert_nil body["meta"]
    assert_equal [
      {"object" => "tag", "id" => @apple.id, "name" => "Apple", "subscription_ids" => [@subscriptions.first.id]},
      {"object" => "tag", "id" => @news.id, "name" => "News", "subscription_ids" => @subscriptions.map(&:id)}
    ], body["data"]
    etag = response.headers["ETag"]
    assert etag.start_with?(%("tags:#{@user.id}:))

    get "/v3/tags", headers: bearer.merge("If-None-Match" => etag)
    assert_response :not_modified

    @feeds.last.tag("Apple", @user)
    get "/v3/tags", headers: bearer.merge("If-None-Match" => etag)
    assert_response :success
  end

  test "renames a tag, which changes its id, and merges into an existing name" do
    patch "/v3/tags/#{@apple.id}", params: {name: "Fruit"}.to_json, headers: json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "Fruit", body["name"]
    assert_equal [@subscriptions.first.id], body["subscription_ids"]
    assert_equal [body["id"]], @user.taggings.where(feed_id: @feeds.first.id).where.not(tag_id: @news.id).pluck(:tag_id).uniq

    patch "/v3/tags/#{body["id"]}", params: {name: "News"}.to_json, headers: json
    assert_response :success
    merged = JSON.parse(response.body)
    assert_equal @news.id, merged["id"]
    assert_equal @subscriptions.map(&:id), merged["subscription_ids"]
    assert_equal 1, @user.taggings.where(feed_id: @feeds.first.id).count
  end

  test "rejects a blank name and a tag the user does not have" do
    patch "/v3/tags/#{@apple.id}", params: {name: " "}.to_json, headers: json
    assert_response :unprocessable_content
    assert_equal "/name", JSON.parse(response.body)["errors"].first["pointer"]

    other = Tag.create!(name: "Elsewhere")
    patch "/v3/tags/#{other.id}", params: {name: "Mine"}.to_json, headers: json
    assert_response :not_found
  end

  test "deletes a tag from every subscription and leaves the subscriptions" do
    delete "/v3/tags/#{@news.id}", headers: bearer

    assert_response :no_content
    assert_equal [@apple.id], @user.taggings.pluck(:tag_id).uniq
    assert_equal 2, @user.subscriptions.count

    delete "/v3/tags/#{@news.id}", headers: bearer
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
