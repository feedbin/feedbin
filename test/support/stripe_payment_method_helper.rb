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
