require "test_helper"
require "ostruct"

class UsersControllerTest < ActionController::TestCase
  include SessionsHelper

  test "should get new user" do
    get :new
    assert_response :success
  end

  test "should create user" do
    plan = plans(:trial)
    assert_difference "User.count", +1 do
      post :create, params: {user: {email: "example@example.com", password: default_password, plan_id: plan.id}}
      assert_redirected_to root_url
    end
    assert signed_in?
  end

  test "should change password" do
    user = users(:ben)
    login_as user
    new_password = "#{default_password} new"
    patch :update, params: {id: user, user: {old_password: default_password, password: new_password}}
    assert_redirected_to settings_account_url
    assert user.reload.authenticate(new_password)
  end

  test "should change plan" do
    user = users(:ann)
    new_plan = plans(:basic_monthly_3)
    user.update(customer_id: Stripe::Customer.create(email: user.email).id)
    login_as user
    Billing::Subscription.stub(:change_price, OpenStruct.new) do
      patch :update, params: {id: user, redirect_to: settings_billing_url, user: {plan_id: new_plan.id}}
    end
    assert_redirected_to settings_billing_url
    assert_equal new_plan, user.reload.plan
  end

  test "should destroy user" do
    user = users(:ben)
    user.update(customer_id: Stripe::Customer.create(email: user.email).id)
    login_as user
    assert_difference "User.count", -1 do
      Sidekiq::Testing.inline! do
        delete :destroy, params: {id: user}
        assert_redirected_to account_closed_public_settings_url
      end
    end
  end
end
