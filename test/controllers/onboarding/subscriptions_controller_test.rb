require "test_helper"

class Onboarding::SubscriptionsControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
    @feed = feeds(:daring_fireball)
    @other_feed = feeds(:kottke)
    # The onboarding form can only ever emit the configured feeds, so the tests
    # subscribe through those rather than through arbitrary urls.
    @configured_url = Feedbin::Application.config.onboarding_feeds.first[:feed_url]
  end

  test "should subscribe to selected feeds" do
    login_as @user
    new_feed = Feed.create!(feed_url: @configured_url)

    assert_difference "Subscription.count", +1 do
      patch :update, params: {feed_url: {new_feed.feed_url => new_feed.feed_url}}, xhr: true
    end
    assert_response :success
    assert @user.subscriptions.exists?(feed: new_feed)
  end

  test "should unsubscribe from deselected feeds" do
    login_as @user
    kottke_url = @other_feed.feed_url
    assert_includes Feedbin::Application.config.onboarding_feeds.map { it[:feed_url] }, kottke_url
    @user.subscriptions.find_or_create_by(feed: @other_feed)

    assert_difference "Subscription.count", -1 do
      patch :update, params: {feed_url: {kottke_url => "0"}}, xhr: true
    end
    assert_response :success
    assert_not @user.subscriptions.exists?(feed: @other_feed)
  end

  test "should handle mixed selections" do
    login_as @user
    new_feed = Feed.create!(feed_url: @configured_url)
    @user.subscriptions.find_or_create_by(feed: @other_feed)

    assert_difference "Subscription.count", 0 do
      patch :update, params: {
        feed_url: {
          new_feed.feed_url => new_feed.feed_url,
          @other_feed.feed_url => "0"
        }
      }, xhr: true
    end
    assert_response :success
    assert @user.subscriptions.exists?(feed: new_feed)
    assert_not @user.subscriptions.exists?(feed: @other_feed)
  end

  test "should not duplicate existing subscriptions" do
    login_as @user
    @user.subscriptions.find_or_create_by(feed: @other_feed)

    assert_no_difference "Subscription.count" do
      patch :update, params: {feed_url: {@other_feed.feed_url => @other_feed.feed_url}}, xhr: true
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

  test "ignores urls that are not configured onboarding feeds" do
    login_as @user
    smuggled = "http://attacker.example.com/anything"
    # No stub: WebMock fails the test if the action fetches this url.

    assert_no_difference "Subscription.count" do
      patch :update, params: {feed_url: {smuggled => smuggled}}, xhr: true
    end
    assert_response :success
    assert_nil Feed.find_by(feed_url: smuggled)
  end

  test "does not fetch one url per key the client sends" do
    login_as @user
    urls = 40.times.to_h { ["http://bulk#{it}.example.com/feed.xml", "subscribe"] }

    assert_no_difference "Subscription.count" do
      patch :update, params: {feed_url: urls}, xhr: true
    end
    assert_response :success
  end
end
