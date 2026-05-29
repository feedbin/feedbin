require "test_helper"
require "ostruct"

class Billing::PaymentMethodTest < ActiveSupport::TestCase
  test "create_setup_intent creates an off_session setup intent for the customer" do
    captured = nil
    Stripe::SetupIntent.stub(:create, ->(params) { captured = params; OpenStruct.new(id: "seti_1") }) do
      intent = Billing::PaymentMethod.create_setup_intent("cus_1")
      assert_equal "seti_1", intent.id
    end
    assert_equal "cus_1", captured[:customer]
    assert_equal "off_session", captured[:usage]
  end

  test "summary returns 'No payment info' when no card is attached" do
    customer = OpenStruct.new(invoice_settings: OpenStruct.new(default_payment_method: nil))
    Stripe::Customer.stub(:retrieve, customer) do
      Stripe::PaymentMethod.stub(:list, OpenStruct.new(data: [])) do
        assert_equal "No payment info", Billing::PaymentMethod.summary("cus_1")
      end
    end
  end

  test "summary returns brand and last-2 for the default card" do
    card = OpenStruct.new(type: "card", card: OpenStruct.new(brand: "visa", last4: "4242"))
    customer = OpenStruct.new(invoice_settings: OpenStruct.new(default_payment_method: "pm_1"))
    Stripe::Customer.stub(:retrieve, customer) do
      Stripe::PaymentMethod.stub(:retrieve, card) do
        assert_equal "Visa ××42", Billing::PaymentMethod.summary("cus_1")
      end
    end
  end

  test "summary returns the humanized type for a non-card default payment method" do
    customer = OpenStruct.new(invoice_settings: OpenStruct.new(default_payment_method: "pm_link"))
    pm = OpenStruct.new(type: "link", card: nil)
    Stripe::Customer.stub(:retrieve, customer) do
      Stripe::PaymentMethod.stub(:retrieve, pm) do
        assert_equal "Link", Billing::PaymentMethod.summary("cus_1")
      end
    end
  end

  test "confirm_and_set_default confirms the setup intent and sets the default payment method" do
    intent = OpenStruct.new(status: "succeeded", payment_method: "pm_9")
    set_args = nil
    Stripe::SetupIntent.stub(:create, intent) do
      Stripe::Customer.stub(:update, ->(id, params) { set_args = [id, params]; OpenStruct.new }) do
        result = Billing::PaymentMethod.confirm_and_set_default(customer_id: "cus_1", confirmation_token: "ct_1")
        assert_equal "succeeded", result.status
      end
    end
    assert_equal "cus_1", set_args[0]
    assert_equal "pm_9", set_args[1][:invoice_settings][:default_payment_method]
  end

  test "confirm_and_set_default does not set a default when the intent is not succeeded" do
    intent = OpenStruct.new(status: "requires_action", payment_method: nil)
    update_called = false
    Stripe::SetupIntent.stub(:create, intent) do
      Stripe::Customer.stub(:update, ->(*) { update_called = true; OpenStruct.new }) do
        Billing::PaymentMethod.confirm_and_set_default(customer_id: "cus_1", confirmation_token: "ct_1")
      end
    end
    refute update_called
  end

  test "finalize retrieves the setup intent and sets the default when succeeded" do
    intent = OpenStruct.new(status: "succeeded", payment_method: "pm_9")
    retrieved_id = nil
    set_args = nil
    Stripe::SetupIntent.stub(:retrieve, ->(id) { retrieved_id = id; intent }) do
      Stripe::Customer.stub(:update, ->(id, params) { set_args = [id, params]; OpenStruct.new }) do
        result = Billing::PaymentMethod.finalize(customer_id: "cus_1", intent_id: "seti_1")
        assert_equal "succeeded", result.status
      end
    end
    assert_equal "seti_1", retrieved_id
    assert_equal "cus_1", set_args[0]
    assert_equal "pm_9", set_args[1][:invoice_settings][:default_payment_method]
  end

  test "finalize does not set a default when the intent is not succeeded" do
    intent = OpenStruct.new(status: "requires_action", payment_method: nil)
    update_called = false
    Stripe::SetupIntent.stub(:retrieve, intent) do
      Stripe::Customer.stub(:update, ->(*) { update_called = true; OpenStruct.new }) do
        result = Billing::PaymentMethod.finalize(customer_id: "cus_1", intent_id: "seti_1")
        assert_equal "requires_action", result.status
      end
    end
    refute update_called
  end
end
