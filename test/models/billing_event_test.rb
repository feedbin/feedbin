require 'test_helper'

class BillingEventTest < ActiveSupport::TestCase
  setup do
    StripeMock.start
    @user = users(:ben)
  end

  teardown do
    StripeMock.stop
  end

  test "charge_succeeded?" do
    Sidekiq::Worker.clear_all
    assert_equal 0, Sidekiq::Extensions::DelayedMailer.jobs.size
    event = StripeMock.mock_webhook_event('charge.succeeded', {customer: @user.customer_id})
    BillingEvent.create(details: event)
    assert_equal 1, Sidekiq::Extensions::DelayedMailer.jobs.size
    Sidekiq::Worker.clear_all
  end

  test "charge_failed?" do
    Sidekiq::Worker.clear_all
    assert_equal 0, Sidekiq::Extensions::DelayedMailer.jobs.size
    event = StripeMock.mock_webhook_event('invoice.payment_failed', {customer: @user.customer_id})
    BillingEvent.create(details: event)
    assert_equal 1, Sidekiq::Extensions::DelayedMailer.jobs.size
    Sidekiq::Worker.clear_all
  end

  test "subscription_deactivated?" do
    assert @user.active?
    event = StripeMock.mock_webhook_event('customer.subscription.updated', {customer: @user.customer_id, status: 'unpaid'})
    BillingEvent.create(details: event)
    assert_not @user.reload.active?
  end

  test "subscription_reactivated?" do
    assert @user.deactivate
    assert_not @user.reload.active?
    event = StripeMock.mock_webhook_event('customer.subscription.updated-custom', {customer: @user.customer_id, status: 'active'})
    BillingEvent.create(details: event)
    assert @user.reload.active?
  end

end
