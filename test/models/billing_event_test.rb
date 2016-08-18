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
    event = StripeMock.mock_webhook_event('charge.succeeded', webhook_defaults)
    BillingEvent.create(info: event.as_json)
    assert_equal 1, Sidekiq::Extensions::DelayedMailer.jobs.size
    Sidekiq::Worker.clear_all
  end

  test "charge_failed?" do
    Sidekiq::Worker.clear_all
    assert_equal 0, Sidekiq::Extensions::DelayedMailer.jobs.size
    event = StripeMock.mock_webhook_event('invoice.payment_failed', webhook_defaults)
    BillingEvent.create(info: event.as_json)
    assert_equal 1, Sidekiq::Extensions::DelayedMailer.jobs.size
    Sidekiq::Worker.clear_all
  end

  test "subscription_deactivated?" do
    assert @user.active?
    event = StripeMock.mock_webhook_event('customer.subscription.updated', webhook_defaults.merge(status: 'unpaid'))
    BillingEvent.create(info: event.as_json)
    assert_not @user.reload.active?
  end

  test "subscription_reactivated?" do
    assert @user.deactivate
    assert_not @user.reload.active?
    event = StripeMock.mock_webhook_event('customer.subscription.updated-custom', webhook_defaults.merge(status: 'active'))
    BillingEvent.create(info: event.as_json)
    assert @user.reload.active?
  end

  private

  def webhook_defaults
    {customer: @user.customer_id}
  end

end
