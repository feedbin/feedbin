require "test_helper"

class Extension::V1::SubscriptionsControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
    @feed = feeds(:daring_fireball)
    @request.headers["Content-Type"] = "application/json"
  end

  test "finds feeds for URL" do
    html_url = "www.example.com/index.html"
    stub_request_file("index.html", html_url)
    stub_request_file("atom.xml", "www.example.com/atom.xml")

    post :new, params: {url: html_url, page_token: @user.page_token}, format: :json
    assert_response :success
    assert_equal @user, assigns(:user)
  end

  test "requires authentication for new" do
    post :new, params: {url: "http://example.com"}, format: :json
    assert_response :unauthorized
  end

  test "includes subscription details for subscribed feeds" do
    @feed.tag("Tech,Design", @user)
    subscription = @user.subscriptions.where(feed: @feed).take!

    result = find_feed

    assert result["subscribed"]
    assert_equal ["Design", "Tech"], result["tags"]
    assert_equal false, result["muted"]
    assert_equal false, result["crawl_error"]
    assert_equal edit_settings_subscription_url(subscription, host: "test.host"), result["manage_url"]
  end

  test "reports muted subscriptions" do
    @user.subscriptions.where(feed: @feed).take!.update!(muted: true)

    assert find_feed["muted"]
  end

  test "reports feeds that fail to crawl" do
    @feed.update!(crawl_data: {error_count: 24})

    assert find_feed["crawl_error"]
  end

  test "omits subscription details for unsubscribed feeds" do
    @user.subscriptions.where(feed: @feed).destroy_all

    result = find_feed

    assert_equal false, result["subscribed"]
    assert_nil result["manage_url"]
    assert_equal [], result["tags"]
    assert_equal false, result["muted"]
    assert_equal false, result["crawl_error"]
  end

  test "resolves subscription details through a redirect" do
    redirected = feeds(:kottke)
    redirected.update!(redirected_to: @feed.feed_url)
    @user.subscriptions.where(feed: @feed).destroy_all
    subscription = @user.subscriptions.create!(feed: redirected)
    redirected.tag("Design", @user)

    result = find_feed

    assert result["subscribed"]
    assert_equal ["Design"], result["tags"]
    assert_equal edit_settings_subscription_url(subscription, host: "test.host"), result["manage_url"]
  end

  test "creates subscription" do
    @user.subscriptions.where(feed: @feed).destroy_all

    feeds_params = {
      @feed.id.to_s => {
        "url" => @feed.feed_url,
        "subscribe" => "1",
        "title" => "Test Feed",
        "media_only" => "0"
      }
    }

    assert_difference "Subscription.count", +1 do
      post :create, params: {
        feeds: feeds_params,
        tags: ["tech", "apple"],
        page_token: @user.page_token
      }, format: :json
      assert_response :success
    end

    subscription = @user.subscriptions.where(feed: @feed).take!
    assert subscription.present?
  end

  test "creates subscription with page token" do
    @user.subscriptions.where(feed: @feed).destroy_all

    feeds_params = {
      @feed.id.to_s => {
        "url" => @feed.feed_url,
        "subscribe" => "1",
        "title" => "Test Feed",
        "media_only" => "0"
      }
    }

    assert_difference "Subscription.count", +1 do
      post :create, params: {
        feeds: feeds_params,
        tags: ["tech"],
        page_token: @user.page_token
      }, format: :json
      assert_response :success
    end
  end

  test "handles invalid feed id" do
    feeds_params = {
      "999999" => {
        "url" => "http://invalid.com/feed.xml",
        "subscribe" => "1",
        "title" => "Invalid",
        "media_only" => "0"
      }
    }

    post :create, params: {
      feeds: feeds_params,
      tags: [],
      page_token: @user.page_token
    }, format: :json
    assert_response :not_found
  end

  test "tags subscriptions" do
    @user.subscriptions.where(feed: @feed).destroy_all

    feeds_params = {
      @feed.id.to_s => {
        "url" => @feed.feed_url,
        "subscribe" => "1",
        "title" => "Test Feed",
        "media_only" => "0"
      }
    }

    post :create, params: {
      feeds: feeds_params,
      tags: ["tech", "apple"],
      page_token: @user.page_token
    }, format: :json

    @user.reload
    tag_names = @user.taggings.where(feed_id: @feed.id).includes(:tag).map { |t| t.tag.name }
    assert_includes tag_names, "tech"
    assert_includes tag_names, "apple"
  end

  test "creates media only subscription" do
    @user.subscriptions.where(feed: @feed).destroy_all

    feeds_params = {
      @feed.id.to_s => {
        "url" => @feed.feed_url,
        "subscribe" => "1",
        "title" => "Test Feed",
        "media_only" => "1"
      }
    }

    post :create, params: {
      feeds: feeds_params,
      tags: [],
      page_token: @user.page_token
    }, format: :json

    subscription = @user.subscriptions.where(feed: @feed).take!
    assert subscription.media_only
  end

  test "requires authentication for create" do
    post :create, params: {feeds: {}, tags: []}, format: :json
    assert_response :unauthorized
  end

  private

  # Feed discovery has its own tests. These cases are about how a discovered
  # feed is described, so hand the controller the feed directly.
  def find_feed
    FeedFinder.stub(:feeds, [@feed]) do
      post :new, params: {url: @feed.feed_url, page_token: @user.page_token}, format: :json
    end
    assert_response :success
    parse_json["feeds"].find { it["id"] == @feed.id }
  end
end