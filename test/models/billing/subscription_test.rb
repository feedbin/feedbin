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
end
