require "test_helper"

class Settings::SubscriptionsControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
  end

  test "should not report an unsubscribe the model refused" do
    login_as @user
    feed = Feed.create(feed_url: SecureRandom.hex, site_url: SecureRandom.hex, title: "Pages")
    subscription = @user.subscriptions.create!(feed: feed, kind: :generated)

    delete :destroy, params: {id: subscription.id}, xhr: true

    assert Subscription.exists?(subscription.id), "generated subscriptions cannot be destroyed"
    assert_nil flash[:notice], "the user must not be told a subscription is gone when it is not"
  end

  test "should not report a bulk unsubscribe that removed nothing" do
    login_as @user
    feed = Feed.create(feed_url: SecureRandom.hex, site_url: SecureRandom.hex, title: "Pages")
    subscription = @user.subscriptions.create!(feed: feed, kind: :generated)

    patch :update_multiple, params: {operation: "unsubscribe", subscription_ids: [subscription.id]}

    assert Subscription.exists?(subscription.id)
    assert_not_equal "You have unsubscribed.", flash[:notice]
  end

  test "a bulk operation only touches the subscriptions the list showed" do
    login_as @user
    feed = Feed.create(feed_url: SecureRandom.hex, site_url: SecureRandom.hex, title: "Pages")
    generated = @user.subscriptions.create!(feed: feed, kind: :generated)

    patch :update_multiple, params: {operation: "mute", include_all: "true"}

    assert_not generated.reload.muted?, "the Pages feed is not in the list the checkbox summarises"
  end

  test "should get index with a page number that cannot be paginated" do
    login_as @user

    ["0", "-1", "abc"].each do |page|
      get :index, params: {page: page}
      assert_response :success, "page=#{page}"
    end
  end

  test "should get index" do
    user = users(:new)
    feeds = create_feeds(user)
    entries = user.entries
    login_as user

    get :index
    assert_response :success
    assert assigns(:subscriptions).present?
  end

  test "should show_updates multiple subscriptions" do
    login_as @user
    ids = @user.subscriptions.pluck(:id)
    post :update_multiple, params: {operation: "show_updates", subscription_ids: ids}
    assert_equal ids.sort, @user.subscriptions.where(show_updates: true).pluck(:id).sort
    assert_redirected_to settings_subscriptions_url
  end

  test "should hide_updates multiple subscriptions" do
    login_as @user
    ids = @user.subscriptions.pluck(:id)
    post :update_multiple, params: {operation: "hide_updates", subscription_ids: ids}
    assert_equal ids.sort, @user.subscriptions.where(show_updates: false).pluck(:id).sort
    assert_redirected_to settings_subscriptions_url
  end

  test "should mute multiple subscriptions" do
    login_as @user
    ids = @user.subscriptions.pluck(:id)
    post :update_multiple, params: {operation: "mute", subscription_ids: ids}
    assert_equal ids.sort, @user.subscriptions.where(muted: true).pluck(:id).sort
    assert_redirected_to settings_subscriptions_url
  end

  test "should unmute multiple subscriptions" do
    login_as @user
    ids = @user.subscriptions.pluck(:id)
    post :update_multiple, params: {operation: "unmute", subscription_ids: ids}
    assert_equal ids.sort, @user.subscriptions.where(muted: false).pluck(:id).sort
    assert_redirected_to settings_subscriptions_url
  end

  test "should destroy multiple subscriptions" do
    login_as @user
    ids = @user.subscriptions.pluck(:id)
    assert_difference "Subscription.count", -ids.length do
      post :update_multiple, params: {operation: "unsubscribe", subscription_ids: ids}
      assert_redirected_to settings_subscriptions_url
    end
  end

  test "should destroy subscription settings" do
    login_as @user
    subscription = @user.subscriptions.first
    assert_difference "Subscription.count", -1 do
      delete :destroy, params: {id: subscription}, xhr: true
      assert_equal assigns(:redirect), settings_subscriptions_url
    end
  end

  test "should get edit" do
    login_as @user
    get :edit, params: {id: @user.subscriptions.first}
    assert_response :success
  end

  test "should refresh favicon" do
    login_as @user
    subscription = @user.subscriptions.first

    assert_difference "FaviconCrawler::Finder.jobs.size", +1 do
      post :refresh_favicon, params: {id: subscription}, xhr: true
      assert_response :success
    end
  end

  test "should unsubscribe from newsletter" do
    user = users(:ben)
    login_as user

    user.newsletter_senders.create!(feed: user.feeds.first, full_token: user.newsletter_authentication_token, email: "example@example.com")
    feed_id = user.newsletter_senders.first.feed_id

    assert user.subscriptions.where(feed_id: feed_id).exists?

    patch :newsletter_senders, params: {id: feed_id, newsletter_sender: {feed_id: "0"}}, xhr: true

    assert_not user.subscriptions.where(feed_id: feed_id).exists?

    patch :newsletter_senders, params: {id: feed_id, newsletter_sender: {feed_id: "1"}}, xhr: true

    assert user.subscriptions.where(feed_id: feed_id).exists?
  end

  test "should not fail when the newsletter sender is toggled on twice" do
    user = users(:ben)
    login_as user

    user.newsletter_senders.create!(feed: user.feeds.first, full_token: user.newsletter_authentication_token, email: "example@example.com")
    feed_id = user.newsletter_senders.first.feed_id
    on = {id: feed_id, newsletter_sender: {feed_id: "1"}}

    patch :newsletter_senders, params: on, xhr: true
    assert_response :success

    assert_no_difference -> { Subscription.count } do
      patch :newsletter_senders, params: on, xhr: true
    end
    assert_response :success
    assert user.subscriptions.where(feed_id: feed_id).exists?
  end

  test "should not fail when the newsletter sender is toggled off twice" do
    user = users(:ben)
    login_as user

    user.newsletter_senders.create!(feed: user.feeds.first, full_token: user.newsletter_authentication_token, email: "example@example.com")
    feed_id = user.newsletter_senders.first.feed_id
    off = {id: feed_id, newsletter_sender: {feed_id: "0"}}

    patch :newsletter_senders, params: off, xhr: true
    assert_response :success

    assert_no_difference -> { Subscription.count } do
      patch :newsletter_senders, params: off, xhr: true
    end
    assert_response :success
    assert_not user.subscriptions.where(feed_id: feed_id).exists?
  end

  test "should not unsubscribe from normal feed" do
    login_as @user
    subscription = @user.subscriptions.first
    assert_no_difference "Subscription.count", +1 do
      patch :newsletter_senders, params: {id: subscription.feed_id, newsletter_sender: {feed_id: "0"}}, xhr: true
    end
  end
end
