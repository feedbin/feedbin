require "test_helper"
require "ostruct"

class Billing::CustomerTest < ActiveSupport::TestCase
  test "create makes a Stripe customer and returns a wrapper" do
    customer = Billing::Customer.create(email: "new@example.com")
    assert_match(/\Acus_/, customer.id)
    assert_equal "new@example.com", customer.email
  end

  test "retrieve loads an existing customer" do
    created = Stripe::Customer.create(email: "x@example.com")
    customer = Billing::Customer.retrieve(created.id)
    assert_equal created.id, customer.id
  end

  test "update_email updates the wrapped customer" do
    customer = Billing::Customer.create(email: "old@example.com")
    customer.update_email("changed@example.com")
    assert_equal "changed@example.com", customer.email
  end

  test "subscription returns nil when the customer has no subscriptions" do
    customer = Billing::Customer.create(email: "s@example.com")
    Stripe::Subscription.stub(:list, OpenStruct.new(data: [])) do
      assert_nil customer.subscription
    end
  end

  test "subscription returns the first subscription when present" do
    customer = Billing::Customer.create(email: "s2@example.com")
    sub = OpenStruct.new(id: "sub_123", status: "active")
    Stripe::Subscription.stub(:list, OpenStruct.new(data: [sub])) do
      assert_equal "sub_123", customer.subscription.id
    end
  end

  test "unpaid? is true when the subscription status is unpaid" do
    customer = Billing::Customer.create(email: "u@example.com")
    sub = OpenStruct.new(id: "sub_1", status: "unpaid")
    Stripe::Subscription.stub(:list, OpenStruct.new(data: [sub])) do
      assert customer.unpaid?
    end
  end
end
