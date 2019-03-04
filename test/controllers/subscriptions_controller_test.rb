require "test_helper"

class SubscriptionsControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
  end

  test "should get index" do
    login_as @user
    get :index, format: :xml
    assert_response :success
  end

  test "should create subscription" do
    html_url = "www.example.com/index.html"
    feed_url = "http://www.example.com/atom.xml"
    stub_request_file("index.html", html_url)
    stub_request_file("atom.xml", feed_url)

    feed = Feed.create(feed_url: feed_url)

    valid_feed_ids = Rails.application.message_verifier(:valid_feed_ids).generate([feed.id])

    params = {
      valid_feed_ids: valid_feed_ids,
      feeds: {
        feed.id => {
          title: "title",
          tags: "Design",
          subscribe: "1",
          media_only: "1",
        },
      },
    }
    login_as @user
    assert_difference "Subscription.count", +1 do
      post :create, params: params, xhr: true
      assert_response :success
    end

    subscription = @user.subscriptions.where(feed: feed).take!
    assert(subscription.media_only, "Subscription should be media only")
  end

  test "should destroy subscription" do
    login_as @user
    subscription = @user.subscriptions.first
    assert_difference "Subscription.count", -1 do
      delete :destroy, params: {id: subscription}, xhr: true
      assert_response :success
    end
  end

end
