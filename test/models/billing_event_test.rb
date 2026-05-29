require "test_helper"

class BillingEventTest < ActiveSupport::TestCase
  setup do
    @user = users(:ben)
    ActionMailer::Base.deliveries.clear
    UpdateStatementDescriptor.clear
  end

  test "charge_succeeded sends a receipt" do
    event = stripe_webhook_event("charge_succeeded", customer: @user.customer_id)
    assert_difference "ActionMailer::Base.deliveries.count", +1 do
      Sidekiq::Testing.inline! do
        BillingEvent.create(info: event)
      end
    end
  end

  test "charge_failed sends a payment-failed notice" do
    event = stripe_webhook_event("invoice_payment_failed", customer: @user.customer_id)
    assert_difference "ActionMailer::Base.deliveries.count", +1 do
      Sidekiq::Testing.inline! do
        BillingEvent.create(info: event)
      end
    end
  end

  test "subscription_deactivated suspends the user" do
    assert @user.active?
    event = stripe_webhook_event("customer_subscription_updated_unpaid", customer: @user.customer_id)
    BillingEvent.create(info: event)
    assert_not @user.reload.active?
  end

  test "subscription_reactivated re-activates the user" do
    @user.deactivate
    assert_not @user.reload.active?
    event = stripe_webhook_event("customer_subscription_updated_reactivated", customer: @user.customer_id)
    BillingEvent.create(info: event)
    assert @user.reload.active?
  end

  test "subscription_reminder emails the user" do
    event = stripe_webhook_event("invoice_upcoming", customer: @user.customer_id)
    assert_difference "ActionMailer::Base.deliveries.count", +1 do
      Sidekiq::Testing.inline! do
        BillingEvent.create(info: event)
      end
    end
  end

  test "invoice_created enqueues the statement descriptor job" do
    event = stripe_webhook_event("invoice_created", customer: @user.customer_id)
    billing_event = assert_difference -> { UpdateStatementDescriptor.jobs.size }, +1 do
      BillingEvent.create(info: event)
    end
    assert_equal billing_event.id, UpdateStatementDescriptor.jobs.first["args"].first
  end
end
