require "test_helper"

class Settings::SubscriptionsControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
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
      assert_redirected_to settings_subscriptions_url
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

    assert_difference "FaviconFetcher.jobs.size", +1 do
      post :refresh_favicon, params: {id: subscription}, xhr: true
      assert_response :success
    end
  end
end
