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

  test "subscribes to several feeds by URL with titles and tags, and leaves an existing one alone" do
    feed = Feed.create!(feed_url: "https://new.example/feed", title: "New")
    other = Feed.create!(feed_url: "https://new.example/podcast", title: "New Podcast")
    @feed.tag(["Old"], @user)
    @subscription.update!(title: "Kept")

    post "/v3/subscriptions", params: {feeds: [{feed_url: feed.feed_url, title: " Mine "}, {feed_url: other.feed_url, title: " "}, {feed_url: @feed.feed_url, title: "Ignored"}], tag_names: ["Apple", "News"]}.to_json, headers: json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [feed.id, other.id, @feed.id], body["applied"]
    assert_equal [], body["skipped"]
    created = @user.subscriptions.find_by!(feed: feed)
    assert_equal ["Mine", nil], [created.title, @user.subscriptions.find_by!(feed: other)[:title]]
    assert_equal %w[Apple News], @user.taggings.where(feed: other).joins(:tag).order("tags.name").pluck("tags.name")
    assert_equal "Kept", @subscription.reload.title
    assert_equal %w[Old], @user.taggings.where(feed: @feed).joins(:tag).pluck("tags.name")
  end

  test "only an exact XML feed URL, or a feed the user can already read, is subscribed" do
    ben = users(:ben)
    private_feed = Feed.create!(feed_url: "https://private.example/feed?token=secret", title: "Private")
    ben.subscriptions.create!(feed: private_feed)
    their_pages = Feed.create!(feed_url: "http://pages.test/theirs", title: "Pages", feed_type: :pages, protected: true)
    ben.subscriptions.create!(feed: their_pages, kind: :generated)
    their_newsletter = Feed.create!(feed_url: "http://sender.example?1", title: "Newsletter", feed_type: :newsletter)
    ben.subscriptions.create!(feed: their_newsletter)
    starred_from = Feed.create!(feed_url: "http://starred.example?2", title: "Starred", feed_type: :newsletter)
    StarredEntry.create_from_owners(@user, starred_from.entries.create!(title: "s", url: "https://starred.example/1", public_id: SecureRandom.hex, entry_id: SecureRandom.hex))
    skipped = ["https://private.example/feed", "HTTPS://private.example/feed?token=secret", their_pages.feed_url, their_newsletter.feed_url, "https://unknown.example/feed"]

    post "/v3/subscriptions", params: {feeds: [*skipped.map { {feed_url: it} }]}.to_json, headers: json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [], body["applied"]
    assert_equal skipped.map { {"feed_url" => it, "reason" => "not_found"} }, body["skipped"]

    post "/v3/subscriptions", params: {feeds: [{feed_url: private_feed.feed_url}, {feed_url: starred_from.feed_url}]}.to_json, headers: json

    assert_equal [private_feed.id, starred_from.id], JSON.parse(response.body)["applied"]
    refute @user.subscriptions.exists?(feed_id: [their_pages.id, their_newsletter.id])
  end

  test "a feed reached through a redirect counts as subscribed" do
    target = Feed.create!(feed_url: "https://moved.example/feed", title: "Moved")
    @feed.update!(redirected_to: target.feed_url)

    post "/v3/subscriptions", params: {feeds: [{feed_url: target.feed_url}]}.to_json, headers: json

    assert_equal [target.id], JSON.parse(response.body)["applied"]
    refute @user.subscriptions.exists?(feed: target)
  end

  test "a subscription another request just created counts as applied" do
    feed = Feed.create!(feed_url: "https://race.example/feed", title: "Race")
    @user.subscriptions.create!(feed: feed)
    subscribe = Api::V3::Subscribe.new(@user, {"feeds" => [{"feed_url" => feed.feed_url}]})

    @user.stub(:existing_subscriptions, {}) do
      assert_equal({applied: [feed.id], skipped: []}, subscribe.subscribe)
    end
    assert_equal 1, @user.subscriptions.where(feed: feed).count
  end

  test "validates the feeds list" do
    [
      [{}, "/feeds", "missing"],
      [{feeds: []}, "/feeds", "invalid_value"],
      [{feeds: [1]}, "/feeds/0", "invalid_value"],
      [{feeds: [{feed_id: 1}]}, "/feeds/0/feed_url", "invalid_value"],
      [{feeds: [{feed_url: ""}]}, "/feeds/0/feed_url", "invalid_value"],
      [{feeds: [{feed_url: "https://a.example/feed", title: 5}]}, "/feeds/0/title", "invalid_value"],
      [{feeds: [{feed_url: "https://a.example/feed"}, {feed_url: "https://a.example/feed"}]}, "/feeds/1/feed_url", "conflict"],
      [{feeds: (1..6).map { {feed_url: "https://a.example/#{it}"} }}, "/feeds", "too_many"],
      [{feeds: [{feed_url: "https://a.example/feed"}], tag_names: "Apple"}, "/tag_names", "invalid_value"],
      [{url: "https://new.example"}, "/feeds", "missing"]
    ].each do |params, pointer, code|
      post "/v3/subscriptions", params: params.to_json, headers: json
      assert_response :unprocessable_content, params.inspect
      assert_equal [pointer, code], JSON.parse(response.body)["errors"].first.values_at("pointer", "code"), params.inspect
    end
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
    assert_equal %w[Apple News], body["data"].map { it["name"] }
    assert_equal [[@subscription.id], [@subscription.id]], body["data"].map { it["subscription_ids"] }
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
    assert_equal ["My Plain"], xml.xpath("/opml/body/outline[@type='rss']").map { it["title"] }
    apple = xml.at("/opml/body/outline[@text='Apple']")
    assert_equal ["https://example.com/feed"], apple.xpath("outline").map { it["xmlUrl"] }
    assert_empty xml.xpath("//outline[@xmlUrl='#{@pages.feed_url}']")
  end

  test "a tag name with a comma stays one tag" do
    put "/v3/subscriptions/#{@subscription.id}/tags", params: {tag_names: ["News, Sports"]}.to_json, headers: json
    assert_response :success
    assert_equal ["News, Sports"], JSON.parse(response.body)["data"].map { it["name"] }

    feed = Feed.create!(feed_url: "https://comma.example/feed", title: "Comma")
    StarredEntry.create_from_owners(@user, feed.entries.create!(title: "c", url: "https://comma.example/1", public_id: SecureRandom.hex, entry_id: SecureRandom.hex))
    post "/v3/subscriptions", params: {feeds: [{feed_url: feed.feed_url}], tag_names: ["Arts, Culture"]}.to_json, headers: json
    assert_equal ["Arts, Culture"], @user.taggings.where(feed: feed).joins(:tag).pluck("tags.name")
  end

  private

  def bearer
    {"Authorization" => "Bearer #{@token.plaintext_token}"}
  end

  def json
    bearer.merge("Content-Type" => "application/json")
  end
end
