require "test_helper"

class Onboarding::SubscriptionsControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
    @feed = feeds(:daring_fireball)
    @other_feed = feeds(:kottke)
  end

  test "should subscribe to selected feeds" do
    login_as @user
    new_feed = Feed.create!(feed_url: "http://example.com/feed.xml")

    assert_difference "Subscription.count", +1 do
      patch :update, params: {feed_url: {new_feed.feed_url => new_feed.feed_url}}, xhr: true
    end
    assert_response :success
    assert @user.subscriptions.exists?(feed: new_feed)
  end

  test "should unsubscribe from deselected feeds" do
    login_as @user
    assert @user.subscriptions.exists?(feed: @feed)

    assert_difference "Subscription.count", -1 do
      patch :update, params: {feed_url: {@feed.feed_url => "0"}}, xhr: true
    end
    assert_response :success
    assert_not @user.subscriptions.exists?(feed: @feed)
  end

  test "should handle mixed selections" do
    login_as @user
    new_feed = Feed.create!(feed_url: "http://example.com/feed.xml")
    @user.subscriptions.find_or_create_by(feed: @feed)

    assert_difference "Subscription.count", 0 do
      patch :update, params: {
        feed_url: {
          new_feed.feed_url => new_feed.feed_url,
          @feed.feed_url => "0"
        }
      }, xhr: true
    end
    assert_response :success
    assert @user.subscriptions.exists?(feed: new_feed)
    assert_not @user.subscriptions.exists?(feed: @feed)
  end

  test "should not duplicate existing subscriptions" do
    login_as @user
    assert @user.subscriptions.exists?(feed: @feed)

    assert_no_difference "Subscription.count" do
      patch :update, params: {feed_url: {@feed.feed_url => @feed.feed_url}}, xhr: true
    end
    assert_response :success
  end

  test "should handle empty params" do
    login_as @user
    assert_no_difference "Subscription.count" do
      patch :update, xhr: true
    end
    assert_response :success
  end
end
