module Billing
  # Card update via SetupIntent, default-PM management, and the card summary
  # shown on the billing page (replaces customer.sources.first).
  class PaymentMethod
    def self.create_setup_intent(customer_id)
      Stripe::SetupIntent.create(customer: customer_id, usage: "off_session")
    end

    # Confirm a SetupIntent with a client-collected ConfirmationToken, then make
    # the resulting payment method the customer's default for invoices.
    def self.confirm_and_set_default(customer_id:, confirmation_token:)
      intent = Stripe::SetupIntent.create(
        customer: customer_id, usage: "off_session",
        confirmation_token: confirmation_token, confirm: true
      )
      if intent.status == "succeeded"
        set_default(customer_id, intent.payment_method)
      end
      intent
    end

    def self.set_default(customer_id, payment_method_id)
      Stripe::Customer.update(customer_id, invoice_settings: {default_payment_method: payment_method_id})
    end

    # "Visa ××42" style summary, or "No payment info".
    def self.summary(customer_id)
      pm = default_card(customer_id)
      return "No payment info" unless pm
      if pm.type == "card" && pm.card
        "#{pm.card.brand.capitalize} ××#{pm.card.last4[-2..]}"
      else
        pm.type.to_s.tr("_", " ").capitalize
      end
    end

    def self.default_card(customer_id)
      customer = Stripe::Customer.retrieve(customer_id)
      default_id = customer.invoice_settings&.default_payment_method
      if default_id
        Stripe::PaymentMethod.retrieve(default_id)
      else
        Stripe::PaymentMethod.list(customer: customer_id, type: "card", limit: 1).data.first
      end
    end
  end
end
