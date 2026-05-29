require "test_helper"
require "ostruct"

class Settings::BillingsControllerTest < ActionController::TestCase
  setup do
    @user = users(:ben)
  end

  test "should get billing" do
    events = [
      stripe_webhook_event("charge_succeeded", customer: @user.customer_id),
      stripe_webhook_event("invoice_payment_succeeded", customer: @user.customer_id)
    ]
    events.each { |event| BillingEvent.create(info: event) }

    login_as @user
    get :index

    assert_response :success
    assert_not_nil assigns(:next_payment_date)
    assert assigns(:billing_events).present?
  end

  test "should get payment_history" do
    events = [
      stripe_webhook_event("charge_succeeded", customer: @user.customer_id),
      stripe_webhook_event("invoice_payment_succeeded", customer: @user.customer_id)
    ]
    events.each { |event| BillingEvent.create(info: event) }

    login_as @user
    get :payment_history

    assert_response :success
    assert assigns(:billing_events).present?
  end

  test "should update plan" do
    new_plan = plans(:basic_yearly_3)
    @user.update(customer_id: Stripe::Customer.create(email: @user.email).id)

    login_as @user
    Billing::Subscription.stub(:change_price, OpenStruct.new) do
      post :update_plan, params: {plan: new_plan.id}
    end
    assert_equal new_plan, @user.reload.plan
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

  test "update_credit_card returns requires_action with a client secret when authentication is needed" do
    user = stripe_user
    user.update(customer_id: Stripe::Customer.create(email: user.email).id)
    login_as user

    intent = OpenStruct.new(status: "requires_action", client_secret: "seti_123_secret_abc")
    Billing::PaymentMethod.stub(:confirm_and_set_default, intent) do
      post :update_credit_card, params: {confirmation_token: "ctoken_123"}, format: :json
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "requires_action", body["status"]
    assert_equal "seti_123_secret_abc", body["client_secret"]
    assert_equal true, body["requires_action"]
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

  test "create_subscription rejects a plan not available to the user without touching Stripe" do
    user = stripe_user
    user.update(customer_id: Stripe::Customer.create(email: user.email).id)
    login_as user

    forbidden = plans(:free)
    called = false
    Billing::Subscription.stub(:subscribe, ->(**) { called = true; OpenStruct.new(status: "succeeded") }) do
      post :create_subscription, params: {plan_id: forbidden.id, confirmation_token: "ct_1"}, format: :json
    end

    assert_response :unprocessable_entity
    refute called, "subscribe must not be called for a forbidden plan"
    assert JSON.parse(response.body)["error"].present?
  end
end
