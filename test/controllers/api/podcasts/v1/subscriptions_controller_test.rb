require "test_helper"
class Api::Podcasts::V1::SubscriptionsControllerTest < ApiControllerTestCase
  setup do
    @user = users(:ben)
    @feeds = create_feeds(@user)
    @entries = @user.entries
    @user.podcast_subscriptions.first.subscribed!
  end

  test "should get index" do
    login_as @user
    get :index, format: :json
    assert_response :success
    data = parse_json

    subscription = @user.podcast_subscriptions.first
    feed = subscription.feed
    assert_equal(subscription.id, data.first.dig("id"))
    assert_equal(feed.id, data.first.dig("feed_id"))
    assert_equal(feed.title, data.first.dig("title"))
    assert_equal(feed.feed_url, data.first.dig("feed_url"))
    assert_equal("subscribed", data.first.dig("status"))
  end

  test "should create" do
    api_content_type
    login_as @user

    feed_url = "http://www.example.com/atom.xml"
    stub_request_file("atom.xml", feed_url)

    assert_difference "PodcastSubscription.count", +1 do
      post :create, params: {feed_url: feed_url, status: "subscribed"}, format: :json
      assert_response :created
    end

    data = parse_json
    assert_equal(feed_url, data.dig("feed_url"))

    assert PodcastSubscription.last.reload.subscribed?, "Subscription should be subscribed"
  end

  test "should delete" do
    api_content_type
    login_as @user

    assert_difference "PodcastSubscription.count", -1 do
      post :destroy, params: {id: @user.subscriptions.first.feed_id}, format: :json
      assert_response :success
    end
  end

  test "should update" do
    api_content_type
    login_as @user

    subscription = @user.podcast_subscriptions.first

    patch :update, params: {id: subscription.feed_id, status: "bookmarked", status_updated_at: Time.now.iso8601(6)}, format: :json
    assert_response :success

    assert subscription.reload.bookmarked?, "Subscription should be bookmarked"
    assert subscription.attribute_changes.present?
    assert_equal("status", subscription.attribute_changes.first.name)
  end

  test "should not update" do
    api_content_type
    login_as @user

    subscription = @user.podcast_subscriptions.first
    subscription.bookmarked!
    subscription.subscribed!

    patch :update, params: {id: subscription.feed_id, status: "bookmarked", status_updated_at: 10.seconds.ago.iso8601(6)}, format: :json
    assert_response :success

    assert_equal("subscribed", subscription.reload.status)
  end
end
