require "test_helper"
require "ostruct"

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

  test "update_credit_card confirms a setup intent and returns json" do
    user = stripe_user
    user.update(customer_id: Stripe::Customer.create(email: user.email).id)
    login_as user

    Billing::PaymentMethod.stub(:confirm_and_set_default, OpenStruct.new(status: "succeeded")) do
      post :update_credit_card, params: {confirmation_token: "ctoken_123"}, format: :json
    end

    assert_response :success
    assert_equal "succeeded", JSON.parse(response.body)["status"]
  end

  test "update_credit_card returns 422 when the confirmation token is missing" do
    user = stripe_user
    user.update(customer_id: Stripe::Customer.create(email: user.email).id)
    login_as user

    post :update_credit_card, params: {}, format: :json

    assert_response :unprocessable_entity
    assert JSON.parse(response.body)["error"].present?
  end

  test "create_subscription activates the existing subscription and returns json" do
    create_stripe_price(plans(:basic_yearly_3))
    user = stripe_user
    user.update(customer_id: Stripe::Customer.create(email: user.email).id)
    login_as user

    Billing::Subscription.stub(:subscribe, OpenStruct.new(status: "succeeded")) do
      post :create_subscription, params: {
        plan_id: plans(:basic_yearly_3).id, confirmation_token: "ctoken_123"
      }, format: :json
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "succeeded", body["status"]
    assert_equal plans(:basic_yearly_3), user.reload.plan
  end
end
