require "test_helper"

class FixFeedsControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
    @subscription = @user.subscriptions.first
    tag = Tag.create!(name: "Tag")
    @tagging = @user.taggings.create!(tag: tag, feed: @subscription.feed)
    @discovered_feed = DiscoveredFeed.create!(site_url: @subscription.feed.site_url, feed_url: "http://example.com/feed")
    @action = @user.actions.create!(feed_ids: [@subscription.feed.id])
    @action_all = @user.actions.create!(all_feeds: true)
  end

  test "replace feed" do
    login_as @user

    stub_request_file("atom.xml", @discovered_feed.feed_url)

    old_feed = @subscription.feed

    patch :update, params: {id: @subscription, subscription: {redirect_to: fix_feeds_url}, discovered_feed: {id: @discovered_feed.id} }

    @subscription.reload
    @action.reload
    @action_all.reload
    @tagging.reload

    assert_not_equal(old_feed, @subscription.feed)
    assert_equal(@tagging.feed, @subscription.feed)

    assert_equal(@discovered_feed.feed_url, @subscription.feed.feed_url)

    assert_equal([@subscription.feed.id], @action.computed_feed_ids)
    assert_equal([@subscription.feed.id], @action_all.computed_feed_ids)

    assert_response :found
  end

  test "ignore suggestion" do
    login_as @user
    @subscription = @user.subscriptions.first
    assert @subscription.fix_suggestion_none?
    patch :destroy, params: {id: @subscription }, xhr: true
    assert @subscription.reload.fix_suggestion_ignored?
    assert_response :ok
  end

  test "unsubscribe" do
    login_as @user
    @subscription = @user.subscriptions.first
    assert_difference -> {Subscription.count}, -1 do
      patch :destroy_subscription, params: {id: @subscription }, xhr: true
    end
    assert_response :ok
  end

  test "replace all" do
    login_as @user
    @subscription = @user.subscriptions.first
    @subscription.fix_suggestion_present!

    assert_difference -> { FeedReplacer.jobs.size }, +1 do
      post :replace_all
    end

    assert @subscription.reload.fix_suggestion_none?
    assert_response :found
  end

end
