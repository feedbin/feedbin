require 'test_helper'

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
    stub_request_file('index.html', html_url)
    stub_request_file('atom.xml', "www.example.com/atom.xml")

    login_as @user
    assert_difference "Subscription.count", +1 do
      xhr :post, :create, subscription: {feeds: {feed_url: html_url}}
      assert_response :success
    end
  end

  test "should destroy subscription" do
    login_as @user
    subscription = @user.subscriptions.first
    assert_difference "Subscription.count", -1 do
      xhr :delete, :destroy, id: subscription
      assert_response :success
    end
  end

  test "should destroy multiple subscriptions" do
    login_as @user
    ids = @user.subscriptions.pluck(:id)
    assert_difference "Subscription.count", -ids.length do
      post :update_multiple, operation: 'unsubscribe', subscription_ids: ids
      assert_redirected_to settings_feeds_url
    end
  end

  test "should show_updates multiple subscriptions" do
    login_as @user
    ids = @user.subscriptions.pluck(:id)
    post :update_multiple, operation: 'show_updates', subscription_ids: ids
    assert_equal ids.sort, @user.subscriptions.where(show_updates: true).pluck(:id).sort
    assert_redirected_to settings_feeds_url
  end

  test "should hide_updates multiple subscriptions" do
    login_as @user
    ids = @user.subscriptions.pluck(:id)
    post :update_multiple, operation: 'hide_updates', subscription_ids: ids
    assert_equal ids.sort, @user.subscriptions.where(show_updates: false).pluck(:id).sort
    assert_redirected_to settings_feeds_url
  end

  test "should mute multiple subscriptions" do
    login_as @user
    ids = @user.subscriptions.pluck(:id)
    post :update_multiple, operation: 'mute', subscription_ids: ids
    assert_equal ids.sort, @user.subscriptions.where(muted: true).pluck(:id).sort
    assert_redirected_to settings_feeds_url
  end

  test "should unmute multiple subscriptions" do
    login_as @user
    ids = @user.subscriptions.pluck(:id)
    post :update_multiple, operation: 'unmute', subscription_ids: ids
    assert_equal ids.sort, @user.subscriptions.where(muted: false).pluck(:id).sort
    assert_redirected_to settings_feeds_url
  end

  test "should get edit" do
    login_as @user
    get :edit, id: @user.subscriptions.first
    assert_response :success
  end

  test "should update subscription" do
    login_as @user
    subscription = @user.subscriptions.first

    attributes = {muted: true, show_updates: false}
    xhr :patch, :update, id: subscription, subscription: attributes

    assert_response :success
    attributes.each do |attribute, value|
      assert_equal(value, subscription.reload.send(attribute))
    end
  end

end