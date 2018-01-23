require 'test_helper'

class UserDeleterTest < ActiveSupport::TestCase

  setup do
    UserDeleter.jobs.clear
    @user = users(:new)
  end

  test "should delete user" do

    StripeMock.start
    customer = Stripe::Customer.create({email: @user.email})
    @user.update(customer_id: customer.id)
    Sidekiq::Testing.inline! do
      assert_difference 'ActionMailer::Base.deliveries.size', +1 do
        UserDeleter.perform_async(@user.id)
      end
    end
    StripeMock.stop

    assert_raise ActiveRecord::RecordNotFound do
      User.find(@user.id)
    end
  end

end
