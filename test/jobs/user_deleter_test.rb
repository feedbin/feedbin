require "test_helper"

class UserDeleterTest < ActiveSupport::TestCase
  test "should delete user" do
    StripeMock.start
    user = users(:ben)
    UserDeleter.new.perform(user.id)
    assert_raise ActiveRecord::RecordNotFound do
      User.find(user.id)
    end
    StripeMock.stop
  end

  test "should send cancelation email" do
    StripeMock.start
    user = users(:ben)
    assert_difference "ActionMailer::Base.deliveries.size", +1 do
      UserDeleter.new.perform(user.id)
    end
    StripeMock.stop
  end

  test "should refund charge" do
    StripeMock.start
    setup_data
    signed_id = Rails.application.message_verifier(:billing_event_id).generate(@billing_event.id)

    UserDeleter.new.perform(@user.id, signed_id)

    charge = Stripe::Charge.retrieve(@charge.id)
    assert charge.refunded, "Charge should have been refunded"

    StripeMock.stop
  end

  test "should not refund charge" do
    StripeMock.start
    setup_data
    signed_id = Rails.application.message_verifier(:billing_event_id).generate(@billing_event.id)

    UserDeleter.new.perform(@user.id, signed_id + "something to make signature invalid")

    charge = Stripe::Charge.retrieve(@charge.id)
    assert_not charge.refunded, "Charge should not have been refunded"

    StripeMock.stop
  end

  def setup_data
    @user = stripe_user
    customer = Stripe::Customer.retrieve(@user.customer_id)
    @charge = Stripe::Charge.create(amount: 1, currency: "usd", customer: customer.id)
    event = StripeMock.mock_webhook_event("charge.succeeded", {customer: @user.customer_id})
    event.data["object"] = @charge.to_h

    @billing_event = BillingEvent.create!(info: event.as_json)
  end
end
