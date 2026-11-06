require "test_helper"

class ApiV3DevicesImportsPagesTest < ActionDispatch::IntegrationTest
  setup do
    host! "api.example.com"
    @user = users(:new)
    @user.setting_on!(:api_v3)
    application = @user.oauth_applications.create!(name: "Reader", redirect_uri: "")
    @token = application.access_tokens.create!(resource_owner_id: @user.id, scopes: "read write account")
  end

  test "registers a device, re-registers the same token, and unregisters it" do
    post "/v3/devices", params: {push_token: "abc123", platform: "ios", app_bundle_id: "com.feedbin.feedbin", model: "iPhone17,1", operating_system: "iOS 27.0"}.to_json, headers: json
    assert_response :created
    body = JSON.parse(response.body)
    assert_equal %w[object id platform app_bundle_id model operating_system created_at], body.keys
    assert_equal ["device", "ios", "com.feedbin.feedbin", "iPhone17,1", "iOS 27.0"], body.values_at("object", "platform", "app_bundle_id", "model", "operating_system")
    assert Device.find(body["id"]).notifier?

    post "/v3/devices", params: {push_token: "ABC123", platform: "ios", app_bundle_id: "com.feedbin.feedbin", model: "iPhone18,1"}.to_json, headers: json
    assert_response :success
    assert_equal body["id"], JSON.parse(response.body)["id"]
    assert_equal "iPhone18,1", JSON.parse(response.body)["model"]

    post "/v3/devices", params: {push_token: "x", platform: "android"}.to_json, headers: json
    assert_response :unprocessable_content

    delete "/v3/devices/#{body["id"]}", headers: bearer
    assert_response :no_content
    delete "/v3/devices/#{body["id"]}", headers: bearer
    assert_response :not_found
  end

  test "an ios device needs its bundle id" do
    post "/v3/devices", params: {push_token: "abc123", platform: "ios"}.to_json, headers: json

    assert_response :unprocessable_content
    error = JSON.parse(response.body)["errors"].first
    assert_equal ["/app_bundle_id", "missing"], error.values_at("pointer", "code")
  end

  test "a device registered through v3 says so" do
    post "/v3/devices", params: {push_token: "abc123", platform: "ios", app_bundle_id: "com.feedbin.app"}.to_json, headers: json

    assert_equal "v3", Device.find(JSON.parse(response.body)["id"]).data["registered_with"]
  end

  test "imports OPML and reports each item" do
    opml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <opml version="1.0"><head><title>Subs</title></head><body>
        <outline text="News" title="News">
          <outline type="rss" text="Daring Fireball" title="Daring Fireball" xmlUrl="https://daringfireball.net/feeds/main" htmlUrl="https://daringfireball.net"/>
        </outline>
        <outline type="rss" text="Old Blog" xmlUrl="https://example.com/rss" htmlUrl="https://example.com"/>
      </body></opml>
    XML

    post "/v3/imports", params: opml, headers: bearer.merge("Content-Type" => "text/x-opml")
    assert_response :accepted
    body = JSON.parse(response.body)
    assert_equal %w[object id status items created_at], body.keys
    assert_equal "pending", body["status"]
    assert_equal [["Daring Fireball", "https://daringfireball.net/feeds/main", "pending", nil, nil], ["Old Blog", "https://example.com/rss", "pending", nil, nil]], body["items"].map { _1.values_at("title", "feed_url", "status", "subscription_id", "message") }

    import = Import.find(body["id"])
    feed = Feed.create!(feed_url: "https://daringfireball.net/feeds/main", title: "DF")
    subscription = @user.subscriptions.create!(feed: feed)
    import.import_items.first.complete!
    import.import_items.last.update!(status: :failed, error_message: "No feed found.")
    import.update!(complete: true)

    get "/v3/imports/#{import.id}", headers: bearer
    body = JSON.parse(response.body)
    assert_equal "complete", body["status"]
    assert_equal [["complete", subscription.id, nil], ["failed", nil, "No feed found."]], body["items"].map { _1.values_at("status", "subscription_id", "message") }

    post "/v3/imports", params: "<html></html>", headers: bearer.merge("Content-Type" => "application/xml")
    assert_response :unsupported_media_type

    Nokogiri.stub(:XML, ->(*) { raise "parsed an oversized body" }) do
      post "/v3/imports", params: "x" * (500.kilobytes + 1), headers: bearer.merge("Content-Type" => "text/x-opml")
    end
    assert_response :unprocessable_content
    assert_equal "too_large", JSON.parse(response.body)["errors"].first["code"]
  end

  test "saves a page into the Pages feed and deletes it" do
    entry = nil
    SavePage.stub(:new, Object.new.tap { |saver|
      saver.define_singleton_method(:perform) do |user_id, url, title, path = nil|
        user = User.find(user_id)
        feed = Feed.create_with(title: "Pages", feed_type: :pages, protected: true).find_or_create_by!(feed_url: "http://pages.test/#{user.id}")
        user.subscriptions.create_with(kind: :generated).find_or_create_by!(feed: feed)
        entry = feed.entries.create_with(title: title, url: url, entry_id: SecureRandom.hex).find_or_create_by!(public_id: SavePage.public_id_for(user, url))
      end
    }) do
      post "/v3/pages", params: {url: "https://example.com/long-read", title: "A Long Read"}.to_json, headers: json
      assert_response :created
      body = JSON.parse(response.body)
      assert_equal ["entry", entry.id, "page", "A Long Read"], body.values_at("object", "id", "kind", "title")

      post "/v3/pages", params: {url: "https://example.com/long-read"}.to_json, headers: json
      assert_response :success
      assert_equal entry.id, JSON.parse(response.body)["id"]
    end

    post "/v3/pages", params: {url: "not a url"}.to_json, headers: json
    assert_response :unprocessable_content

    delete "/v3/pages/#{entry.id}", headers: bearer
    assert_response :no_content
    refute Entry.exists?(entry.id)

    other = Feed.create!(feed_url: "https://o.example/f").entries.create!(title: "o", url: "https://o.example/1", public_id: SecureRandom.hex, entry_id: SecureRandom.hex)
    delete "/v3/pages/#{other.id}", headers: bearer
    assert_response :not_found

    their_pages = Feed.create!(feed_url: "http://pages.test/theirs", title: "Pages", feed_type: :pages, protected: true)
    users(:ben).subscriptions.create!(feed: their_pages, kind: :generated)
    @user.subscriptions.create!(feed: their_pages)
    theirs = their_pages.entries.create!(title: "t", url: "https://t.example/1", public_id: SecureRandom.hex, entry_id: SecureRandom.hex)
    delete "/v3/pages/#{theirs.id}", headers: bearer
    assert_response :not_found
    assert Entry.exists?(theirs.id)
  end

  # SavePage saves YouTube pages twice, which clears previously_new_record?.
  test "a new page filled in after it is created is still 201" do
    SavePage.stub(:new, Object.new.tap { |saver|
      saver.define_singleton_method(:perform) do |user_id, url, title, path = nil|
        user = User.find(user_id)
        feed = Feed.create_with(title: "Pages", feed_type: :pages, protected: true).find_or_create_by!(feed_url: "http://pages.test/#{user.id}")
        user.subscriptions.create_with(kind: :generated).find_or_create_by!(feed: feed)
        entry = feed.entries.create_with(title: title, url: url, entry_id: SecureRandom.hex).find_or_create_by!(public_id: SavePage.public_id_for(user, url))
        entry.update!(title: "From the embed")
        entry
      end
    }) do
      post "/v3/pages", params: {url: "https://www.youtube.com/watch?v=abc"}.to_json, headers: json
      assert_response :created

      post "/v3/pages", params: {url: "https://www.youtube.com/watch?v=abc"}.to_json, headers: json
      assert_response :success
    end
  end

  test "Airshow registers for podcast pushes" do
    original = ENV["APPLE_PUSH_TOPIC_PODCAST"]
    ENV["APPLE_PUSH_TOPIC_PODCAST"] = "com.feedbin.airshow"
    post "/v3/devices", params: {push_token: "abc123", platform: "ios", app_bundle_id: "com.feedbin.airshow"}.to_json, headers: json

    assert_response :created
    assert_equal "ios", JSON.parse(response.body)["platform"]
    assert Device.find(JSON.parse(response.body)["id"]).podcast?
  ensure
    ENV["APPLE_PUSH_TOPIC_PODCAST"] = original
  end

  test "a page already in an unsubscribed Pages feed answers 200" do
    url = "https://example.com/again"
    feed = Feed.create!(title: "Pages", feed_type: :pages, protected: true, feed_url: "http://pages.test/#{@user.id}")
    existing = feed.entries.create!(title: "Again", url: url, entry_id: SecureRandom.hex, public_id: SavePage.public_id_for(@user, url))

    SavePage.stub(:new, Object.new.tap { |saver| saver.define_singleton_method(:perform) { |*| existing } }) do
      post "/v3/pages", params: {url: url}.to_json, headers: json
    end

    assert_response :success
    assert_equal existing.id, JSON.parse(response.body)["id"]
  end

  private

  def bearer
    {"Authorization" => "Bearer #{@token.plaintext_token}"}
  end

  def json
    bearer.merge("Content-Type" => "application/json")
  end
end
