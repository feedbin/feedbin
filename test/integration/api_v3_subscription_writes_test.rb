require "test_helper"

class ApiV3SubscriptionWritesTest < ActionDispatch::IntegrationTest
  setup do
    host! "api.example.com"
    @user = users(:new)
    @user.setting_on!(:api_v3)
    @feed = Feed.create!(feed_url: "https://example.com/feed", host: "example.com", title: "Example", site_url: "https://example.com")
    @subscription = @user.subscriptions.create!(feed: @feed)
    @pages = Feed.create!(feed_url: "http://pages.test/abc", title: "Pages", feed_type: :pages)
    @generated = @user.subscriptions.create!(feed: @pages, kind: :generated)
    application = @user.oauth_applications.create!(name: "Reader", redirect_uri: "")
    @token = application.access_tokens.create!(resource_owner_id: @user.id, scopes: "read write account")
  end

  test "shows one subscription and 404s for another user's" do
    get "/v3/subscriptions/#{@subscription.id}", params: {expand: "feed"}, headers: bearer
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @subscription.id, body["id"]
    assert_equal @feed.id, body["feed"]["id"]

    other = users(:ben).subscriptions.create!(feed: Feed.create!(feed_url: "https://other.example/feed"))
    get "/v3/subscriptions/#{other.id}", headers: bearer
    assert_response :not_found
  end

  test "subscribes by a feed id it offered in a 300, with tags, and finds the existing subscription" do
    feed = Feed.create!(feed_url: "https://new.example/feed", title: "New")
    other = Feed.create!(feed_url: "https://new.example/podcast", title: "New Podcast")
    FeedFinder.stub(:feeds, [feed, other]) do
      post "/v3/subscriptions", params: {url: "https://new.example"}.to_json, headers: json
    end
    assert_response :multiple_choices

    post "/v3/subscriptions", params: {feed_id: feed.id, tag_names: ["Apple", "News"]}.to_json, headers: json
    assert_response :created
    body = JSON.parse(response.body)
    assert_equal feed.id, body["feed_id"]
    assert_equal %w[Apple News], Tag.where(id: body["tag_ids"]).order(:name).pluck(:name)

    post "/v3/subscriptions", params: {feed_id: feed.id}.to_json, headers: json.merge({})
    assert_response :success
    assert_equal body["id"], JSON.parse(response.body)["id"]

    post "/v3/subscriptions", params: {feed_id: 0}.to_json, headers: json
    assert_response :not_found
  end

  test "a feed id that was not offered and is not readable is not found" do
    ben = users(:ben)
    private_feed = Feed.create!(feed_url: "https://private.example/feed?token=secret", title: "Private")
    ben.subscriptions.create!(feed: private_feed)
    their_pages = Feed.create!(feed_url: "http://pages.test/theirs", title: "Pages", feed_type: :pages, protected: true)
    ben.subscriptions.create!(feed: their_pages, kind: :generated)

    [private_feed, their_pages].each do |feed|
      post "/v3/subscriptions", params: {feed_id: feed.id}.to_json, headers: json
      assert_response :not_found
    end
    refute @user.subscriptions.exists?(feed_id: [private_feed.id, their_pages.id])

    starred_from = Feed.create!(feed_url: "https://starred.example/feed", title: "Starred")
    StarredEntry.create_from_owners(@user, starred_from.entries.create!(title: "s", url: "https://starred.example/1", public_id: SecureRandom.hex, entry_id: SecureRandom.hex))
    post "/v3/subscriptions", params: {feed_id: starred_from.id}.to_json, headers: json
    assert_response :created
  end

  test "subscribes by url when discovery finds one feed, 300 when it finds several" do
    found = Feed.create!(feed_url: "https://marco.example/rss", title: "Marco")
    second = Feed.create!(feed_url: "https://marco.example/podcast", title: "Marco Podcast")

    FeedFinder.stub(:feeds, [found]) do
      post "/v3/subscriptions", params: {url: "https://marco.example"}.to_json, headers: json
    end
    assert_response :created
    assert_equal found.id, JSON.parse(response.body)["feed_id"]

    FeedFinder.stub(:feeds, [found, second]) do
      post "/v3/subscriptions", params: {url: "https://marco.example"}.to_json, headers: json
    end
    assert_response :multiple_choices
    body = JSON.parse(response.body)
    assert_equal "list", body["object"]
    assert_equal [found.id, second.id], body["data"].map { _1["id"] }
    assert_equal ["feed"], body["data"].map { _1["object"] }.uniq
    assert_nil body["meta"]

    FeedFinder.stub(:feeds, []) do
      post "/v3/subscriptions", params: {url: "https://nothing.example"}.to_json, headers: json
    end
    assert_response :not_found
  end

  test "searches known feeds for words" do
    found = Feed.create!(feed_url: "https://daring.example/rss", title: "Daring Fireball")
    Feed.stub(:search, Feed.where(id: found.id)) do
      post "/v3/subscriptions", params: {url: "daring fireball"}.to_json, headers: json
    end
    assert_response :created
    assert_equal found.id, JSON.parse(response.body)["feed_id"]
  end

  test "requires exactly one of url and feed_id" do
    post "/v3/subscriptions", params: {}.to_json, headers: json
    assert_response :unprocessable_content
    post "/v3/subscriptions", params: {url: "x", feed_id: 1}.to_json, headers: json
    assert_response :unprocessable_content
  end

  test "updates the custom title and preferences as a merge patch" do
    patch "/v3/subscriptions/#{@subscription.id}", params: {custom_title: "Mine", preferences: {muted: true}}.to_json, headers: json
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal ["Mine", "Mine", true, false, true], [body["title"], body["custom_title"], *body["preferences"].values_at("muted", "media_only", "show_updates")]

    patch "/v3/subscriptions/#{@subscription.id}", params: {custom_title: nil}.to_json, headers: json.merge("Content-Type" => "application/merge-patch+json")
    body = JSON.parse(response.body)
    assert_equal ["Example", nil, true], [body["title"], body["custom_title"], body["preferences"]["muted"]]

    patch "/v3/subscriptions/#{@subscription.id}", params: {preferences: {muted: "yes"}}.to_json, headers: json
    assert_response :unprocessable_content
    assert_equal "/preferences/muted", JSON.parse(response.body)["errors"].first["pointer"]
  end

  test "the Pages subscription is not a v3 subscription" do
    patch "/v3/subscriptions/#{@generated.id}", params: {custom_title: "Nope"}.to_json, headers: json
    assert_response :not_found

    delete "/v3/subscriptions/#{@generated.id}", headers: bearer
    assert_response :not_found
    assert @generated.reload.persisted?
  end

  test "sets the whole tag set and lists the tags after" do
    @feed.tag("Old", @user)

    put "/v3/subscriptions/#{@subscription.id}/tags", params: {tag_names: ["Apple", " News ", ""]}.to_json, headers: json
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal %w[Apple News], body["data"].map { _1["name"] }
    assert_equal [[@subscription.id], [@subscription.id]], body["data"].map { _1["subscription_ids"] }
    assert_nil body["meta"]
    refute @user.taggings.joins(:tag).where(tags: {name: "Old"}).exists?

    put "/v3/subscriptions/#{@subscription.id}/tags", params: {tag_names: []}.to_json, headers: json
    assert_equal [], JSON.parse(response.body)["data"]
    assert_equal 0, @user.taggings.count

    put "/v3/subscriptions/#{@subscription.id}/tags", params: {tag_names: "Apple"}.to_json, headers: json
    assert_response :unprocessable_content
  end

  test "deletes a subscription and keeps starred entries readable" do
    entry = @feed.entries.create!(title: "Keep", url: "https://example.com/keep", public_id: SecureRandom.hex, entry_id: SecureRandom.hex)
    StarredEntry.create_from_owners(@user, entry)

    delete "/v3/subscriptions/#{@subscription.id}", headers: bearer
    assert_response :no_content
    refute Subscription.exists?(@subscription.id)
    assert @user.reload.can_read_entry?(entry.id)

    delete "/v3/subscriptions/#{@subscription.id}", headers: bearer
    assert_response :not_found
  end

  test "exports OPML with tags as outlines" do
    @feed.tag("Apple", @user)
    untagged = Feed.create!(feed_url: "https://plain.example/feed", title: "Plain", site_url: "https://plain.example")
    @user.subscriptions.create!(feed: untagged, title: "My Plain")

    get "/v3/subscriptions.opml", headers: bearer

    assert_response :success
    assert_equal "text/x-opml", response.media_type
    xml = Nokogiri::XML(response.body)
    assert_equal "Feedbin", xml.at("head title").text
    assert_equal ["My Plain"], xml.xpath("/opml/body/outline[@type='rss']").map { _1["title"] }
    apple = xml.at("/opml/body/outline[@text='Apple']")
    assert_equal ["https://example.com/feed"], apple.xpath("outline").map { _1["xmlUrl"] }
    assert_empty xml.xpath("//outline[@xmlUrl='#{@pages.feed_url}']")
  end

  test "a tag name with a comma stays one tag" do
    put "/v3/subscriptions/#{@subscription.id}/tags", params: {tag_names: ["News, Sports"]}.to_json, headers: json
    assert_response :success
    assert_equal ["News, Sports"], JSON.parse(response.body)["data"].map { _1["name"] }

    feed = Feed.create!(feed_url: "https://comma.example/feed", title: "Comma")
    StarredEntry.create_from_owners(@user, feed.entries.create!(title: "c", url: "https://comma.example/1", public_id: SecureRandom.hex, entry_id: SecureRandom.hex))
    post "/v3/subscriptions", params: {feed_id: feed.id, tag_names: ["Arts, Culture"]}.to_json, headers: json
    assert_equal ["Arts, Culture"], Tag.where(id: JSON.parse(response.body)["tag_ids"]).pluck(:name)
  end

  test "a discovery failure is not found" do
    [OpenSSL::SSL::SSLError, Errno::ECONNREFUSED, Timeout::Error].each do |error|
      FeedFinder.stub(:feeds, ->(*) { raise error }) do
        post "/v3/subscriptions", params: {url: "https://broken.example"}.to_json, headers: json
      end
      assert_response :not_found, error.name
    end

    Feed.stub(:search, ->(*) { raise Search::Connection::ResponseError, "down" }) do
      post "/v3/subscriptions", params: {url: "daring fireball"}.to_json, headers: json
    end
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
