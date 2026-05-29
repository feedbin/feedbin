require "test_helper"
require "ostruct"

class CancelBillingTest < ActiveSupport::TestCase
  test "deletes the stripe customer" do
    deleted = false
    customer = Object.new
    customer.define_singleton_method(:delete) { deleted = true }
    Stripe::Customer.stub(:retrieve, customer) do
      CancelBilling.new.perform("cus_123")
    end
    assert deleted
  end
end
