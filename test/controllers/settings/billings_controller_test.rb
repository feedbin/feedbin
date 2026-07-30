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

    stub_payment_methods do |attachments, detachments|
      user.stripe_token = "pm_original"
      user.save

      login_as user
      post :update_credit_card, params: {stripe_token: "pm_replacement"}
      assert_redirected_to settings_billing_url

      assert_equal ["pm_original", "pm_replacement"], attachments.map { _1[:payment_method] }
      assert_equal [user.customer_id, user.customer_id], attachments.map { _1[:customer] }
      assert_equal ["pm_original"], detachments, "the replaced card should not stay attached"
    end

    customer = Stripe::Customer.retrieve(user.customer_id)
    assert_equal "pm_replacement", customer.invoice_settings.default_payment_method
    StripeMock.stop
  end

  test "should pay an open invoice with the newly saved card" do
    with_card_saving_user("retry-paid@example.com") do |user|
      stub_open_invoice(paid: true) do
        post :update_credit_card, params: {stripe_token: "pm_replacement"}
      end
    end

    assert_redirected_to settings_billing_url
    assert_equal "Your card has been updated.", flash[:notice]
  end

  test "should send the customer to authenticate when the retried invoice needs it" do
    with_card_saving_user("retry-action@example.com") do |user|
      stub_open_invoice(paid: false) do
        post :update_credit_card, params: {stripe_token: "pm_replacement"}
      end
    end

    assert_redirected_to authenticate_settings_billing_url
  end

  test "should treat an authentication_required decline as needing authentication" do
    with_card_saving_user("retry-auth-error@example.com") do |user|
      stub_open_invoice(error_code: "authentication_required") do
        post :update_credit_card, params: {stripe_token: "pm_replacement"}
      end
    end

    assert_redirected_to authenticate_settings_billing_url
  end

  test "should surface a real decline from the retried invoice" do
    with_card_saving_user("retry-declined@example.com") do |user|
      stub_open_invoice(error_code: "card_declined") do
        post :update_credit_card, params: {stripe_token: "pm_replacement"}
      end

      assert_not user.reload.suspended, "an account that wasn't suspended shouldn't become suspended"
    end

    assert_redirected_to edit_settings_billing_url
    assert_equal "Your card was declined.", flash[:alert]
  end

  test "should re-suspend a suspended account when the replacement card declines" do
    with_card_saving_user("declined-while-suspended@example.com", suspended: true) do |user|
      assert user.reload.suspended

      # update_billing lifts the suspension mid-request, so this only stays true
      # if the decline puts it back.
      stub_open_invoice(error_code: "card_declined") do
        post :update_credit_card, params: {stripe_token: "pm_replacement"}
      end

      assert user.reload.suspended, "a card that doesn't work must not buy access"
    end

    assert_redirected_to edit_settings_billing_url
    assert_equal "Your card was declined.", flash[:alert]
  end

  test "should keep a suspended account suspended until authentication finishes" do
    with_card_saving_user("suspended-needs-auth@example.com", suspended: true) do |user|
      stub_open_invoice(paid: false) do
        post :update_credit_card, params: {stripe_token: "pm_replacement"}
      end

      assert user.reload.suspended, "an unauthenticated payment must not buy access"
    end

    assert_redirected_to authenticate_settings_billing_url
  end

  test "should report the save honestly when collecting the invoice errors" do
    with_card_saving_user("collect-error@example.com") do |user|
      stub_open_invoice(error: Stripe::APIConnectionError.new("Connection error")) do
        post :update_credit_card, params: {stripe_token: "pm_replacement"}
      end
    end

    assert_redirected_to settings_billing_url
    assert_equal "Your card has been updated, but we could not collect the open invoice. Please try again.", flash[:alert]
  end

  test "should re-suspend a suspended account when collecting the invoice errors" do
    with_card_saving_user("collect-error-suspended@example.com", suspended: true) do |user|
      stub_open_invoice(error: Stripe::APIConnectionError.new("Connection error")) do
        post :update_credit_card, params: {stripe_token: "pm_replacement"}
      end

      assert user.reload.suspended, "an invoice that wasn't collected must not buy access"
    end

    assert_redirected_to settings_billing_url
  end

  test "should not collect an invoice that dunning is not working on" do
    paid = []

    with_card_saving_user("stale-invoice@example.com") do |user|
      # The subscription is settled; whatever else may be sitting open on the
      # customer is not this app's to charge.
      stub_dunning_invoice(status: "paid") do
        Stripe::Invoice.stub(:pay, ->(*) { paid << :charged }) do
          post :update_credit_card, params: {stripe_token: "pm_replacement"}
        end
      end
    end

    assert_empty paid, "only the subscription's latest_invoice should ever be collected"
    assert_redirected_to settings_billing_url
    assert_equal "Your card has been updated.", flash[:notice]
  end

  test "should not collect a lapsed invoice that reopen_account just wrote off" do
    paid = []

    with_card_saving_user("reanchored@example.com") do |user|
      Customer.stub_any_instance(:unpaid?, true) do
        Customer.stub_any_instance(:reopen_account, :reanchored) do
          Customer.stub_any_instance(:pay_open_invoice, -> { paid << :charged }) do
            post :update_credit_card, params: {stripe_token: "pm_replacement"}
          end
        end
      end
    end

    assert_empty paid, "re-anchoring bills a fresh period, so charging the lapsed invoice would double up"
    assert_redirected_to settings_billing_url
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

  test "should authenticate a payment that needs it" do
    login_as @user

    stub_authentication_intent(client_secret: "pi_123_secret") do
      get :authenticate
    end

    assert_response :success
    assert_equal "pi_123_secret", assigns(:client_secret)
    assert_match "pi_123_secret", response.body
  end

  test "should skip authenticate when the intent no longer needs action" do
    login_as @user

    stub_authentication_intent(status: "succeeded") do
      get :authenticate
    end

    assert_redirected_to settings_billing_url
  end

  test "should skip authenticate when there is no open invoice" do
    # A real mock customer, so this exercises the nothing-owed path rather than
    # tripping over a customer that doesn't exist.
    with_card_saving_user("nothing-owed@example.com") do |user|
      get :authenticate
    end

    assert_redirected_to settings_billing_url
    assert_equal "There's no payment waiting to be confirmed.", flash[:notice]
  end

  test "should recover when authenticate cannot reach Stripe" do
    login_as @user

    Customer.stub(:retrieve, ->(*) { raise Stripe::APIConnectionError.new("Connection error") }) do
      get :authenticate
    end

    assert_redirected_to settings_billing_url
    assert_equal "Could not load the payment. Please try again.", flash[:alert]
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

  test "should show no payment info when the customer has no card" do
    StripeMock.start
    plan = plans(:trial)
    create_stripe_plan(plan)

    user = User.create(
      email: "no-card@example.com",
      password: default_password,
      plan: plan
    )
    customer = Stripe::Customer.create({email: user.email})
    user.update(customer_id: customer.id)

    login_as user
    get :payment_details, format: :js, xhr: true

    assert_response :success
    assert_equal "No payment info", assigns(:message)
    StripeMock.stop
  end

  private

  # A signed-in user with a Stripe customer and a card already on file, set up so
  # the block can post a replacement card.
  def with_card_saving_user(email, suspended: false)
    StripeMock.start
    create_stripe_plan(plans(:trial))

    user = User.create(
      email: email,
      password: default_password,
      plan: plans(:trial)
    )

    stub_payment_methods do
      user.stripe_token = "pm_original"
      user.save
      user.update_columns(suspended: true) if suspended

      login_as user
      yield user
    end

    StripeMock.stop
  end
end
