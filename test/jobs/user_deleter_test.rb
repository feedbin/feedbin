require "test_helper"

class UserDeleterTest < ActiveSupport::TestCase
  test "should delete user" do
    user = users(:ben)
    UserDeleter.new.perform(user.id)
    assert_raise ActiveRecord::RecordNotFound do
      User.find(user.id)
    end
  end

  test "should send cancelation email" do
    user = users(:ben)
    assert_difference "ActionMailer::Base.deliveries.size", +1 do
      UserDeleter.new.perform(user.id)
    end
  end

  test "should refund charge" do
    setup_data
    signed_id = Rails.application.message_verifier(:billing_event_id).generate(@billing_event.id)

    refunded_charge = nil
    refund = ->(charge:) { refunded_charge = charge }
    Stripe::Refund.stub(:create, refund) do
      UserDeleter.new.perform(@user.id, signed_id)
    end

    assert_equal @charge_id, refunded_charge, "Charge should have been refunded"
  end

  test "should not refund charge" do
    setup_data
    signed_id = Rails.application.message_verifier(:billing_event_id).generate(@billing_event.id)

    refunded_charge = nil
    refund = ->(charge:) { refunded_charge = charge }
    Stripe::Refund.stub(:create, refund) do
      UserDeleter.new.perform(@user.id, signed_id + "something to make signature invalid")
    end

    assert_nil refunded_charge, "Charge should not have been refunded"
  end

  def setup_data
    @user = stripe_user
    @charge_id = "ch_test_123"
    event = stripe_webhook_event("charge_succeeded", customer: @user.customer_id)
    event["data"]["object"]["id"] = @charge_id
    @billing_event = BillingEvent.create!(info: event.as_json)
  end
end
