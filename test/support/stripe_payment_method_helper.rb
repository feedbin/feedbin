module StripePaymentMethodHelper
  # stripe-ruby-mock has no PaymentMethod handler, so the two PaymentMethod calls
  # made while saving a card are stubbed at the library boundary. The
  # `Stripe::Customer.update` that sets `invoice_settings.default_payment_method`
  # still runs against the mock, so the result of saving a card is assertable.
  #
  # Yields an array that records each attach, as {payment_method:, customer:}.
  def stub_payment_methods(brand: "Visa", last4: "4242")
    attachments = []

    attach = lambda do |payment_method, params = {}, _opts = {}|
      attachments << {payment_method: payment_method, customer: params[:customer]}
      nil
    end

    retrieve = lambda do |payment_method, _opts = {}|
      Stripe::PaymentMethod.construct_from(
        id: payment_method,
        object: "payment_method",
        type: "card",
        card: {brand: brand, last4: last4}
      )
    end

    Stripe::PaymentMethod.stub(:attach, attach) do
      Stripe::PaymentMethod.stub(:retrieve, retrieve) do
        yield attachments
      end
    end
  end

  # Gives Customer#subscription a `latest_invoice` pointing at an invoice in
  # `status` — stripe-ruby-mock's subscriptions predate that field. Also fails the
  # test if anything reaches for the newest-open-invoice query this replaced.
  def stub_dunning_invoice(status: "open", payment_intent: "pi_test", invoice_id: "in_open")
    subscription = Stripe::StripeObject.construct_from(
      id: "sub_test",
      object: "subscription",
      latest_invoice: invoice_id
    )

    invoice = Stripe::Invoice.construct_from(
      id: invoice_id,
      object: "invoice",
      status: status,
      payment_intent: payment_intent
    )

    no_list = ->(*) { raise "collection must gate on the subscription's latest_invoice, not the newest open invoice" }

    Customer.stub_any_instance(:subscription, subscription) do
      Stripe::Invoice.stub(:list, no_list) do
        Stripe::Invoice.stub(:retrieve, invoice) do
          yield
        end
      end
    end
  end

  # stripe-ruby-mock has no PaymentIntent handler, so the intent read is stubbed.
  def stub_authentication_intent(status: "requires_action", client_secret: "pi_test_secret", payment_intent: "pi_test")
    intent = Stripe::PaymentIntent.construct_from(
      id: "pi_test",
      object: "payment_intent",
      status: status,
      client_secret: client_secret
    )

    # The lookup hangs off a Customer instance now, and these tests don't care
    # which customer — stub_dunning_invoice supplies the subscription.
    wrapped = Customer.new(Stripe::Customer.construct_from(id: "cus_test", object: "customer"))

    stub_dunning_invoice(payment_intent: payment_intent) do
      Customer.stub(:retrieve, wrapped) do
        Stripe::PaymentIntent.stub(:retrieve, intent) do
          yield
        end
      end
    end
  end

  # Exercises the retry that follows a card update. stripe-ruby-mock can't pay an
  # invoice, so the pay call is stubbed. `error_code` makes it raise, standing in
  # for a decline or an authentication demand.
  def stub_open_invoice(paid: false, error_code: nil)
    pay = lambda do |_id, _params = {}, _opts = {}|
      raise Stripe::CardError.new("Your card was declined.", nil, code: error_code) if error_code
      Stripe::Invoice.construct_from(id: "in_open", object: "invoice", status: paid ? "paid" : "open", paid: paid)
    end

    stub_dunning_invoice do
      Stripe::Invoice.stub(:pay, pay) do
        yield
      end
    end
  end

  def stub_setup_intent(client_secret: "seti_test_secret")
    intent = Stripe::SetupIntent.construct_from(
      id: "seti_test",
      object: "setup_intent",
      client_secret: client_secret
    )
    Stripe::SetupIntent.stub(:create, intent) do
      yield intent
    end
  end
end
