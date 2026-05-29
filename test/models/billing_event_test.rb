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

  test "setup_intent_succeeded sets the default payment method and reactivates a suspended user" do
    @user.deactivate
    assert_not @user.reload.active?

    set_default_args = nil
    Billing::PaymentMethod.stub(:set_default, ->(cid, pm) { set_default_args = [cid, pm] }) do
      BillingEvent.create(info: stripe_webhook_event("setup_intent_succeeded", customer: @user.customer_id))
    end

    assert @user.reload.active?
    assert_equal [@user.customer_id, "pm_test_1"], set_default_args
  end

  test "payment_intent_succeeded reactivates a suspended user" do
    @user.deactivate
    set_default_args = nil
    Billing::PaymentMethod.stub(:set_default, ->(cid, pm) { set_default_args = [cid, pm] }) do
      BillingEvent.create(info: stripe_webhook_event("payment_intent_succeeded", customer: @user.customer_id))
    end
    assert @user.reload.active?
    assert_equal [@user.customer_id, "pm_test_1"], set_default_args
  end

  test "payment_intent_succeeded is a no-op for an active (non-suspended) user" do
    assert @user.active?
    set_default_called = false
    Billing::PaymentMethod.stub(:set_default, ->(*) { set_default_called = true }) do
      assert_nothing_raised do
        BillingEvent.create(info: stripe_webhook_event("payment_intent_succeeded", customer: @user.customer_id))
      end
    end
    assert @user.reload.active?
    refute set_default_called, "backstop must not touch Stripe for a healthy active user"
  end
end
