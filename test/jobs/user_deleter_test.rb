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
      UserDeleter.perform_async(@user.id)
    end
    StripeMock.stop

    assert_raise ActiveRecord::RecordNotFound do
      User.find(@user.id)
    end
  end

end
