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
    create_stripe_plan(plan)

    user = User.create(
      email: "cc@example.com",
      password: default_password,
      plan: plan
    )

    stub_payment_methods do |attachments|
      user.stripe_token = "pm_original"
      user.save

      login_as user
      post :update_credit_card, params: {stripe_token: "pm_replacement"}
      assert_redirected_to settings_billing_url

      assert_equal ["pm_original", "pm_replacement"], attachments.map { _1[:payment_method] }
      assert_equal [user.customer_id, user.customer_id], attachments.map { _1[:customer] }
    end

    customer = Stripe::Customer.retrieve(user.customer_id)
    assert_equal "pm_replacement", customer.invoice_settings.default_payment_method
    StripeMock.stop
  end

  test "should get edit with a setup intent url on the form" do
    login_as @user
    get :edit

    assert_response :success
    assert_match create_setup_intent_settings_billing_path, response.body
  end

  test "should get billing with a setup intent url on the subscribe form" do
    StripeMock.start
    plan = plans(:trial)
    create_stripe_plan(plan)

    user = User.create(
      email: "trial@example.com",
      password: default_password,
      plan: plan
    )

    login_as user
    get :index

    assert_response :success
    assert_match create_setup_intent_settings_billing_path, response.body
    StripeMock.stop
  end

  test "should create a setup intent" do
    login_as @user

    stub_setup_intent(client_secret: "seti_123_secret") do
      post :create_setup_intent
    end

    assert_response :success
    assert_equal "seti_123_secret", response.parsed_body["client_secret"]
  end

  test "should get payment details for a card saved as a payment method" do
    StripeMock.start
    plan = plans(:trial)
    create_stripe_plan(plan)

    user = User.create(
      email: "pm@example.com",
      password: default_password,
      plan: plan
    )

    stub_payment_methods(brand: "Visa", last4: "4242") do
      user.stripe_token = "pm_saved"
      user.save

      login_as user
      get :payment_details, format: :js, xhr: true
    end

    assert_response :success
    assert_equal "Visa ××42", assigns(:message)
    StripeMock.stop
  end

  test "should get payment details for a card saved before payment methods" do
    StripeMock.start
    stripe_helper = StripeMock.create_test_helper
    customer = Stripe::Customer.create({email: @user.email, source: stripe_helper.generate_card_token(last4: "9999")})
    @user.update(customer_id: customer.id)

    login_as @user
    get :payment_details, format: :js, xhr: true

    assert_response :success
    assert_equal "Visa ××99", assigns(:message)
    StripeMock.stop
  end
end
