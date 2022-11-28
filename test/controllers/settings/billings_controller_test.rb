require "test_helper"

class Settings::BillingsControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
  end

  test "should get billing" do
    StripeMock.start
    events = [
      StripeMock.mock_webhook_event("charge.succeeded", {customer: @user.customer_id}),
      StripeMock.mock_webhook_event("invoice.payment_succeeded", {customer: @user.customer_id})
    ]
    events.each do |event|
      BillingEvent.create(info: event.as_json)
    end

    login_as @user
    get :index

    assert_response :success
    assert_not_nil assigns(:next_payment_date)
    assert assigns(:billing_events).present?
    StripeMock.stop
  end

  test "should get payment_history" do
    StripeMock.start
    events = [
      StripeMock.mock_webhook_event("charge.succeeded", {customer: @user.customer_id}),
      StripeMock.mock_webhook_event("invoice.payment_succeeded", {customer: @user.customer_id})
    ]
    events.each do |event|
      BillingEvent.create(info: event.as_json)
    end

    login_as @user
    get :payment_history

    assert_response :success
    assert assigns(:billing_events).present?
    StripeMock.stop
  end

  test "should update plan" do
    StripeMock.start
    stripe_helper = StripeMock.create_test_helper

    plans = {
      original: plans(:basic_monthly_3),
      new: plans(:basic_yearly_3)
    }
    plans.each do |_, plan|
      create_stripe_plan(plan)
    end

    customer = Stripe::Customer.create({email: @user.email, plan: plans[:original].stripe_id, source: stripe_helper.generate_card_token})
    @user.update(customer_id: customer.id)
    @user.reload.inspect

    login_as @user
    post :update_plan, params: {plan: plans[:new].id}
    assert_equal plans[:new], @user.reload.plan
    StripeMock.stop
  end

  test "should update credit card" do
    StripeMock.start
    plan = plans(:trial)
    last4 = "1234"
    card_1 = StripeMock.generate_card_token(last4: "4242", exp_month: 99, exp_year: 3005)
    card_2 = StripeMock.generate_card_token(last4: last4, exp_month: 99, exp_year: 3005)
    create_stripe_plan(plan)

    user = User.create(
      email: "cc@example.com",
      password: default_password,
      plan: plan
    )
    user.stripe_token = card_1
    user.save

    login_as user
    post :update_credit_card, params: {stripe_token: card_2}
    assert_redirected_to settings_billing_url

    customer = Stripe::Customer.retrieve(user.customer_id)
    assert_equal last4, customer.sources.data.first.last4
    StripeMock.stop
  end
end
