require 'test_helper'

class UsersControllerTest < ActionController::TestCase

  include SessionsHelper

  test "should get new user" do
    get :new
    assert_response :success
  end

  test "should create user" do
    StripeMock.start
    plan = plans(:trial)
    Stripe::Plan.create(id: plan.stripe_id, amount: plan.price)
    assert_difference "User.count", +1 do
      post :create, user: {email: 'example@example.com', password: default_password, plan_id: plan.id}
      assert_redirected_to root_url
    end
    assert signed_in?
    StripeMock.stop
  end

  test "should change password" do
    user = users(:ben)
    login_as user
    new_password = "#{default_password} new"
    patch :update, id: user, user: {old_password: default_password, password: new_password}
    assert_redirected_to settings_account_url
    assert user.reload.authenticate(new_password)
  end

  test "should change plan" do
    StripeMock.start
    user = users(:ann)
    new_plan = plans(:basic_monthly_2)
    last4 = "1234"
    token = StripeMock.generate_card_token(last4: last4, exp_month: 99, exp_year: 3005)
    Stripe::Plan.create(id: user.plan.stripe_id, amount: user.plan.price)
    Stripe::Plan.create(id: new_plan.stripe_id, amount: new_plan.price)

    customer = Stripe::Customer.create({email: user.email, plan: user.plan.stripe_id})
    user.update(customer_id: customer.id)

    redirect_url = settings_billing_url

    login_as user
    patch :update, id: user, redirect_to: redirect_url, user: {stripe_token: token, plan_id: new_plan.id}
    assert_redirected_to redirect_url
    assert_equal new_plan, user.reload.plan

    customer = Stripe::Customer.retrieve(user.customer_id)
    assert_equal last4, customer.cards.first.last4

    StripeMock.stop
  end

  test "should destroy user" do
    StripeMock.start
    user = users(:ben)
    login_as user
    assert_difference "User.count", -1 do
      delete :destroy, id: user
      assert_redirected_to root_url
    end
    StripeMock.stop
  end

end
