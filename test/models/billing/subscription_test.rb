require "test_helper"
require "ostruct"

class Billing::SubscriptionTest < ActiveSupport::TestCase
  test "create_trialing creates a trialing default_incomplete subscription with the price and trial end" do
    captured = nil
    Stripe::Subscription.stub(:create, ->(params) { captured = params; OpenStruct.new(id: "sub_123") }) do
      sub = Billing::Subscription.create_trialing(
        customer_id: "cus_1", price_id: "price_1", trial_end: Time.at(1_900_000_000)
      )
      assert_equal "sub_123", sub.id
    end
    assert_equal "cus_1", captured[:customer]
    assert_equal [{price: "price_1"}], captured[:items]
    assert_equal 1_900_000_000, captured[:trial_end]
    assert_equal "default_incomplete", captured[:payment_behavior]
  end

  test "change_price swaps the subscription item price keeping a future trial" do
    existing = OpenStruct.new(items: OpenStruct.new(data: [OpenStruct.new(id: "si_1")]))
    captured_id = nil
    captured = nil
    Stripe::Subscription.stub(:retrieve, existing) do
      Stripe::Subscription.stub(:update, ->(id, params) { captured_id = id; captured = params; OpenStruct.new(id: id) }) do
        Billing::Subscription.change_price(subscription_id: "sub_9", price_id: "price_new", trial_end: 1.year.from_now)
      end
    end
    assert_equal "sub_9", captured_id
    assert_equal [{id: "si_1", price: "price_new"}], captured[:items]
    assert_equal "none", captured[:proration_behavior]
    assert_kind_of Integer, captured[:trial_end]
  end

  test "change_price ends the trial immediately when trial_end has passed" do
    existing = OpenStruct.new(items: OpenStruct.new(data: [OpenStruct.new(id: "si_1")]))
    captured = nil
    Stripe::Subscription.stub(:retrieve, existing) do
      Stripe::Subscription.stub(:update, ->(_id, params) { captured = params; OpenStruct.new }) do
        Billing::Subscription.change_price(subscription_id: "sub_9", price_id: "price_new", trial_end: 1.day.ago)
      end
    end
    assert_equal "now", captured[:trial_end]
  end

  test "trial_end_param returns now for nil or past, unix for future" do
    assert_equal "now", Billing::Subscription.trial_end_param(nil)
    assert_equal "now", Billing::Subscription.trial_end_param(1.day.ago)
    future = 1.day.from_now
    assert_equal future.to_i, Billing::Subscription.trial_end_param(future)
  end

  test "reopen_account pays an open invoice" do
    invoice = OpenStruct.new(id: "in_1", status: "open")
    paid_id = nil
    Stripe::Invoice.stub(:list, OpenStruct.new(data: [invoice])) do
      Stripe::Invoice.stub(:pay, ->(id) { paid_id = id; OpenStruct.new }) do
        Billing::Subscription.reopen_account("cus_1")
      end
    end
    assert_equal "in_1", paid_id
  end

  test "reopen_account pays an uncollectible invoice" do
    invoice = OpenStruct.new(id: "in_2", status: "uncollectible")
    paid_id = nil
    Stripe::Invoice.stub(:list, OpenStruct.new(data: [invoice])) do
      Stripe::Invoice.stub(:pay, ->(id) { paid_id = id; OpenStruct.new }) do
        Billing::Subscription.reopen_account("cus_1")
      end
    end
    assert_equal "in_2", paid_id
  end

  test "reopen_account restarts the billing cycle for a draft invoice on an unpaid subscription" do
    invoice = OpenStruct.new(id: "in_3", status: "draft")
    sub = OpenStruct.new(id: "sub_1")
    captured = nil
    Stripe::Invoice.stub(:list, OpenStruct.new(data: [invoice])) do
      Stripe::Subscription.stub(:list, OpenStruct.new(data: [sub])) do
        Stripe::Subscription.stub(:update, ->(id, params) { captured = [id, params]; OpenStruct.new }) do
          Billing::Subscription.reopen_account("cus_1")
        end
      end
    end
    assert_equal "sub_1", captured[0]
    assert_equal "now", captured[1][:billing_cycle_anchor]
    assert_equal "none", captured[1][:proration_behavior]
  end

  test "reopen_account does nothing when there is no invoice" do
    Stripe::Invoice.stub(:list, OpenStruct.new(data: [])) do
      assert_nil Billing::Subscription.reopen_account("cus_1")
    end
  end

  test "subscribe (future trial) confirms a setup intent, sets the default PM, and changes price keeping the trial" do
    intent = OpenStruct.new(status: "succeeded", payment_method: "pm_9")
    set_default_args = nil
    change_price_args = nil
    Stripe::SetupIntent.stub(:create, intent) do
      Billing::PaymentMethod.stub(:set_default, ->(cid, pm) { set_default_args = [cid, pm] }) do
        Billing::Subscription.stub(:change_price, ->(**kw) { change_price_args = kw }) do
          result = Billing::Subscription.subscribe(
            customer_id: "cus_1", subscription_id: "sub_1", price_id: "price_new",
            confirmation_token: "ct_1", trial_end: 30.days.from_now
          )
          assert_equal "succeeded", result.status
        end
      end
    end
    assert_equal ["cus_1", "pm_9"], set_default_args
    assert_equal "sub_1", change_price_args[:subscription_id]
    assert_equal "price_new", change_price_args[:price_id]
  end

  test "subscribe (future trial) does not set default or change price when the setup intent is not succeeded" do
    intent = OpenStruct.new(status: "requires_action", payment_method: nil)
    set_default_called = false
    change_price_called = false
    Stripe::SetupIntent.stub(:create, intent) do
      Billing::PaymentMethod.stub(:set_default, ->(*) { set_default_called = true }) do
        Billing::Subscription.stub(:change_price, ->(**) { change_price_called = true }) do
          result = Billing::Subscription.subscribe(
            customer_id: "cus_1", subscription_id: "sub_1", price_id: "price_new",
            confirmation_token: "ct_1", trial_end: 30.days.from_now
          )
          assert_equal "requires_action", result.status
        end
      end
    end
    refute set_default_called
    refute change_price_called
  end

  test "subscribe (expired trial) ends the trial now and confirms the invoice payment intent" do
    existing = OpenStruct.new(items: OpenStruct.new(data: [OpenStruct.new(id: "si_1")]))
    updated = OpenStruct.new(
      latest_invoice: OpenStruct.new(
        confirmation_secret: OpenStruct.new(client_secret: "pi_ABC_secret_xyz")
      )
    )
    pi = OpenStruct.new(status: "succeeded", payment_method: "pm_5")
    update_args = nil
    confirm_args = nil
    set_default_args = nil
    Stripe::Subscription.stub(:retrieve, existing) do
      Stripe::Subscription.stub(:update, ->(id, params) { update_args = [id, params]; updated }) do
        Stripe::PaymentIntent.stub(:confirm, ->(pi_id, **kw) { confirm_args = [pi_id, kw]; pi }) do
          Billing::PaymentMethod.stub(:set_default, ->(cid, pm) { set_default_args = [cid, pm] }) do
            result = Billing::Subscription.subscribe(
              customer_id: "cus_1", subscription_id: "sub_1", price_id: "price_new",
              confirmation_token: "ct_1", trial_end: 1.day.ago
            )
            assert_equal "succeeded", result.status
          end
        end
      end
    end
    assert_equal "sub_1", update_args[0]
    assert_equal [{id: "si_1", price: "price_new"}], update_args[1][:items]
    assert_equal "now", update_args[1][:trial_end]
    assert_equal "default_incomplete", update_args[1][:payment_behavior]
    assert_equal "pi_ABC", confirm_args[0]
    assert_equal "ct_1", confirm_args[1][:confirmation_token]
    assert_equal ["cus_1", "pm_5"], set_default_args
  end

  test "subscribe (expired trial) returns a succeeded intent without confirming when the invoice has no confirmation secret" do
    existing = OpenStruct.new(items: OpenStruct.new(data: [OpenStruct.new(id: "si_1")]))
    updated = OpenStruct.new(latest_invoice: OpenStruct.new(confirmation_secret: nil))
    confirm_called = false
    Stripe::Subscription.stub(:retrieve, existing) do
      Stripe::Subscription.stub(:update, updated) do
        Stripe::PaymentIntent.stub(:confirm, ->(*) { confirm_called = true; raise "should not confirm" }) do
          result = Billing::Subscription.subscribe(
            customer_id: "cus_1", subscription_id: "sub_1", price_id: "price_new",
            confirmation_token: "ct_1", trial_end: 1.day.ago
          )
          assert_equal "succeeded", result.status
        end
      end
    end
    refute confirm_called, "PaymentIntent.confirm must not be called for a zero-amount invoice"
  end

  test "finalize (seti_ succeeded) sets the default PM and changes the price" do
    intent = OpenStruct.new(status: "succeeded", payment_method: "pm_9")
    set_default_args = nil
    change_price_args = nil
    Stripe::SetupIntent.stub(:retrieve, intent) do
      Billing::PaymentMethod.stub(:set_default, ->(cid, pm) { set_default_args = [cid, pm] }) do
        Billing::Subscription.stub(:change_price, ->(**kw) { change_price_args = kw }) do
          result = Billing::Subscription.finalize(
            customer_id: "cus_1", subscription_id: "sub_1", price_id: "price_new",
            trial_end: 30.days.from_now, intent_id: "seti_x"
          )
          assert_equal "succeeded", result.status
        end
      end
    end
    assert_equal ["cus_1", "pm_9"], set_default_args
    assert_equal "sub_1", change_price_args[:subscription_id]
    assert_equal "price_new", change_price_args[:price_id]
  end

  test "finalize (pi_ succeeded) sets the default PM but does not change the price" do
    intent = OpenStruct.new(status: "succeeded", payment_method: "pm_5")
    set_default_args = nil
    change_price_called = false
    Stripe::PaymentIntent.stub(:retrieve, intent) do
      Billing::PaymentMethod.stub(:set_default, ->(cid, pm) { set_default_args = [cid, pm] }) do
        Billing::Subscription.stub(:change_price, ->(**) { change_price_called = true }) do
          result = Billing::Subscription.finalize(
            customer_id: "cus_1", subscription_id: "sub_1", price_id: "price_new",
            trial_end: 1.day.ago, intent_id: "pi_x"
          )
          assert_equal "succeeded", result.status
        end
      end
    end
    assert_equal ["cus_1", "pm_5"], set_default_args
    refute change_price_called, "change_price must not run on the immediate (pi_) path"
  end

  test "finalize does neither when the intent is not succeeded" do
    intent = OpenStruct.new(status: "requires_action", payment_method: nil)
    set_default_called = false
    change_price_called = false
    Stripe::SetupIntent.stub(:retrieve, intent) do
      Billing::PaymentMethod.stub(:set_default, ->(*) { set_default_called = true }) do
        Billing::Subscription.stub(:change_price, ->(**) { change_price_called = true }) do
          result = Billing::Subscription.finalize(
            customer_id: "cus_1", subscription_id: "sub_1", price_id: "price_new",
            trial_end: 30.days.from_now, intent_id: "seti_x"
          )
          assert_equal "requires_action", result.status
        end
      end
    end
    refute set_default_called
    refute change_price_called
  end
end
