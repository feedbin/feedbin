require 'test_helper'

class SettingsControllerTest < ActionController::TestCase

  setup do
    @user = users(:ben)
  end

  test "should get settings" do
    login_as @user
    get :settings
    assert_response :success
  end

  test "should get account" do
    login_as @user
    get :account
    assert_response :success
  end

  test "should get appearance" do
    login_as @user
    get :appearance
    assert_response :success
  end

  test "should get feeds" do
    user = users(:new)
    feeds = create_feeds(user)
    entries = user.entries
    login_as user

    get :feeds
    assert_response :success
    assert assigns(:subscriptions).present?
  end

  test "should get billing" do
    StripeMock.start
    events = [
      StripeMock.mock_webhook_event('charge.succeeded', {customer: @user.customer_id}),
      StripeMock.mock_webhook_event('invoice.payment_succeeded', {customer: @user.customer_id})
    ]
    events.each do |event|
      BillingEvent.create(details: event)
    end
    StripeMock.stop

    login_as @user
    get :billing

    assert_response :success
    assert_not_nil assigns(:next_payment_date)
    assert assigns(:billing_events).present?
  end

  test "should import/export" do
    skip 'TODO'
  end

  test "should mark_favicon_complete" do
    login_as @user
    post :mark_favicon_complete
    assert_response :success
  end

end
