require "test_helper"

class CancelBillingTest < ActiveSupport::TestCase
  test "should cancel subscription" do
    StripeMock.start
    plan = plans(:trial)
    create_stripe_plan(plan)

    user = User.create(
      email: "cc@example.com",
      password: default_password,
      plan: plan,
    )

    CancelBilling.new.perform(user.customer_id)

    customer = Stripe::Customer.retrieve(user.customer_id)
    assert customer.deleted
    StripeMock.stop
  end
end
