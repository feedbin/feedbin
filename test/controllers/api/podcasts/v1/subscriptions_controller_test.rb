require "test_helper"
class Api::Podcasts::V1::SubscriptionsControllerTest < ApiControllerTestCase
  setup do
    @user = users(:new)
    @feeds = create_feeds(@user)
    @entries = @user.entries
    @user.subscriptions.first.subscribed!
  end

  test "should get index" do
    login_as @user
    get :index, format: :json
    assert_response :success
    data = parse_json

    subscription = @user.subscriptions.first
    feed = subscription.feed
    assert_equal(subscription.id, data.first.dig("id"))
    assert_equal(feed.id, data.first.dig("feed_id"))
    assert_equal(feed.title, data.first.dig("title"))
    assert_equal(feed.feed_url, data.first.dig("feed_url"))
    assert_equal("subscribed", data.first.dig("show_status"))
  end

  test "should create" do
    api_content_type
    login_as @user

    feed_url = "http://www.example.com/atom.xml"
    stub_request_file("atom.xml", feed_url)

    assert_difference "Subscription.count", +1 do
      post :create, params: {feed_url: feed_url, show_status: "subscribed"}, format: :json
      assert_response :found
    end

    data = parse_json
    assert_equal(feed_url, data.dig("feed_url"))
    assert_equal("subscribed", Subscription.last.show_status)
  end

  test "should delete" do
    api_content_type
    login_as @user

    assert_difference "Subscription.count", -1 do
      post :destroy, params: {id: @user.subscriptions.first.id}, format: :json
      assert_response :success
    end
  end

  test "should update" do
    api_content_type
    login_as @user

    subscription = @user.subscriptions.first

    patch :update, params: {id: subscription.id, show_status: "bookmarked"}, format: :json
    assert_response :success

    assert_equal("bookmarked", subscription.reload.show_status)
  end
end
