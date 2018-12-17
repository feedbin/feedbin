require "test_helper"

class BillingEventTest < ActiveSupport::TestCase
  setup do
    StripeMock.start
    @user = users(:ben)
  end

  teardown do
    StripeMock.stop
  end

  test "charge_succeeded?" do
    StripeMock.start

    invoice = Stripe::Invoice.create
    event = StripeMock.mock_webhook_event("charge.succeeded", webhook_defaults)
    event["data"]["object"]["invoice"] = invoice.id
    assert_difference "ActionMailer::Base.deliveries.count", +1 do
      Sidekiq::Testing.inline! do
        BillingEvent.create(info: event.as_json)
      end
    end

    StripeMock.stop
  end

  test "charge_failed?" do
    event = StripeMock.mock_webhook_event("invoice.payment_failed", webhook_defaults)
    assert_difference "ActionMailer::Base.deliveries.count", +1 do
      Sidekiq::Testing.inline! do
        BillingEvent.create(info: event.as_json)
      end
    end
  end

  test "subscription_deactivated?" do
    assert @user.active?
    event = StripeMock.mock_webhook_event("customer.subscription.updated", webhook_defaults.merge(status: "unpaid"))
    BillingEvent.create(info: event.as_json)
    assert_not @user.reload.active?
  end

  test "subscription_reactivated?" do
    assert @user.deactivate
    assert_not @user.reload.active?
    event = StripeMock.mock_webhook_event("customer.subscription.updated-custom", webhook_defaults.merge(status: "active"))
    BillingEvent.create(info: event.as_json)
    assert @user.reload.active?
  end

  private

  def webhook_defaults
    {customer: @user.customer_id}
  end
end
