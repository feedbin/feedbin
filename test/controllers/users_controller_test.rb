require "test_helper"

class UsersControllerTest < ActionController::TestCase
  include SessionsHelper

  test "should get new user" do
    get :new
    assert_response :success
  end

  test "should create user" do
    StripeMock.start
    plan = plans(:trial)
    create_stripe_plan(plan)
    assert_difference "User.count", +1 do
      post :create, params: {user: {email: "example@example.com", password: default_password, plan_id: plan.id}}
      assert_redirected_to root_url
    end
    assert signed_in?
    StripeMock.stop
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
    StripeMock.start
    stripe_helper = StripeMock.create_test_helper
    user = users(:ann)
    new_plan = plans(:basic_monthly_3)
    last4 = "1234"
    token = stripe_helper.generate_card_token(last4: last4, exp_month: 99, exp_year: 3005)
    create_stripe_plan(user.plan)
    create_stripe_plan(new_plan)

    customer = Stripe::Customer.create({email: user.email, plan: user.plan.stripe_id})
    user.update(customer_id: customer.id)

    redirect_url = settings_billing_url

    login_as user
    patch :update, params: {id: user, redirect_to: redirect_url, user: {stripe_token: token, plan_id: new_plan.id}}
    assert_redirected_to redirect_url
    assert_equal new_plan, user.reload.plan

    customer = Stripe::Customer.retrieve(user.customer_id)
    assert_equal last4, customer.sources.data.first.last4

    StripeMock.stop
  end

  test "should destroy user" do
    StripeMock.start
    user = users(:ben)
    customer = Stripe::Customer.create({email: user.email})
    user.update(customer_id: customer.id)

    login_as user
    assert_difference "User.count", -1 do
      Sidekiq::Testing.inline! do
        delete :destroy, params: {id: user}
        assert_redirected_to account_closed_public_settings_url
      end
    end
    StripeMock.stop
  end
end
