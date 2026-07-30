# wraps a Stripe::Customer instance
class Customer
  # Stripe reports "the customer has to authenticate this payment" as an error
  # rather than a return value, under a code that varies by API version. Neither
  # of these means the card was declined.
  AUTHENTICATION_ERROR_CODES = ["authentication_required", "invoice_payment_intent_requires_action"].freeze

  attr_reader :customer

  delegate :id, to: :customer
  delegate :sources, to: :customer

  def self.create(email, plan, trial_end)
    new_customer = new(Stripe::Customer.create({email: email}))
    Stripe::Subscription.create(
      customer: new_customer.id,
      plan: plan,
      trial_end: trial_end.to_i
    )
    new_customer
  end

  def self.retrieve(customer_id)
    new(Stripe::Customer.retrieve(customer_id))
  end

  # When a recurring charge needs authentication Stripe leaves the invoice open
  # with its PaymentIntent in `requires_action`, and that intent's client secret
  # is what the browser needs to run the challenge. Returns nil when nothing is
  # waiting, so this doubles as the check for whether to offer authentication.
  # Neither `invoice.payment_intent` nor PaymentIntents themselves exist at the
  # pinned API version, so both reads happen at the newer one.
  def self.authentication_client_secret(customer_id)
    options = {stripe_version: STRIPE_INTENTS_API_VERSION}
    invoice = dunning_invoice(customer_id, options)
    payment_intent_id = invoice && invoice[:payment_intent]
    return nil if payment_intent_id.blank?

    intent = Stripe::PaymentIntent.retrieve(payment_intent_id, options)
    intent.client_secret if intent.status == "requires_action"
  end

  # The subscription's `latest_invoice` is the one Stripe's dunning is working on,
  # and the only one this app has any business collecting or authenticating.
  # Asking for "the newest open invoice on the customer" instead would also pick
  # up a period that was written off, a stale plan-change invoice, or anything
  # raised by hand — and charge it the next time the customer saves a card.
  #
  # Returns nil unless that invoice is open, i.e. unless something is actually
  # owed. The subscription is re-read rather than taken from the customer object
  # so this doesn't depend on the pinned version's expansion.
  def self.dunning_invoice(customer_id, options)
    subscription = Stripe::Subscription.list({customer: customer_id, limit: 1}, options).data.first
    latest_invoice_id = subscription && subscription[:latest_invoice]
    return nil if latest_invoice_id.blank?

    invoice = Stripe::Invoice.retrieve(latest_invoice_id, options)
    invoice if invoice.status == "open"
  end

  def initialize(customer)
    @customer = customer
  end

  def unpaid?
    customer.try(:subscriptions).try(:first).try(:status) == "unpaid"
  end

  # Recovery for a fully lapsed account — one whose retries are spent, which is
  # what `unpaid?` means. Returns :reopened when the outstanding invoice was put
  # back into collection, :reanchored when the billing period was reset instead,
  # or nil when neither applied.
  #
  # `:reanchored` matters to the caller: resetting the anchor bills a fresh period
  # and writes off the lapsed one, so collecting the old invoice afterwards would
  # charge the customer twice for the same gap.
  #
  # `invoice.closed` only exists at the pinned API version — it was replaced by
  # `auto_advance`, so this branch quietly stops matching if the pin ever moves.
  def reopen_account
    invoice = Stripe::Invoice.list(customer: id, limit: 1).first
    if !invoice.paid && invoice.closed && invoice.status != "draft"
      invoice.closed = false
      invoice.save
      :reopened
    elsif (!invoice.paid && invoice.attempt_count >= 4) || invoice.status == "draft"
      Stripe::Subscription.update(invoice.subscription,
        {
          billing_cycle_anchor: "now",
          proration_behavior: "none"
        }
      )
      # Re-anchoring bills a fresh period and abandons this one, so say so rather
      # than leaving the invoice outstanding forever. Voiding is only valid on an
      # open invoice — a draft has nothing to write off. Done after the re-anchor
      # so a failure here still leaves the account recovered.
      Stripe::Invoice.void_invoice(invoice.id, {}, {stripe_version: STRIPE_INTENTS_API_VERSION}) if invoice.status == "open"
      :reanchored
    end
  end

  # Retry the customer's open invoice against whatever payment method is now the
  # default. Stripe doesn't do this on its own: an `authentication_required`
  # decline schedules no retry, and a past_due subscription never reattempts an
  # invoice whose attempts are spent — so without this a customer who responds to
  # a failed charge by updating their card is left with the invoice still open.
  #
  # Returns :paid, :requires_action when the bank wants the customer to
  # authenticate, or nil when there was nothing owed. A genuine decline raises
  # Stripe::CardError, the same as any other charge in this controller.
  def pay_open_invoice
    options = {stripe_version: STRIPE_INTENTS_API_VERSION}
    invoice = self.class.dunning_invoice(id, options)
    return nil unless invoice

    Stripe::Invoice.pay(invoice.id, {}, options).paid ? :paid : :requires_action
  rescue Stripe::StripeError => exception
    raise unless AUTHENTICATION_ERROR_CODES.include?(exception.code)
    :requires_action
  end

  def update_email(email)
    customer.email = email
    customer.save
  end

  # `payment_method` is a PaymentMethod id (pm_…) from a SetupIntent confirmed in
  # the browser, not a card token. Stripe pays subscription invoices with
  # `invoice_settings.default_payment_method` in preference to the customer's
  # legacy `default_source`, so setting it here is what switches the card over.
  def update_source(payment_method)
    options = {stripe_version: STRIPE_INTENTS_API_VERSION}
    Stripe::PaymentMethod.attach(payment_method, {customer: id}, options)
    Stripe::Customer.update(id, {invoice_settings: {default_payment_method: payment_method}}, options)
  end

  # Cards saved through the SetupIntent flow are PaymentMethods, which don't show
  # up in `sources`. Cards saved before it are still legacy sources.
  def card_description
    card = default_payment_method_card || sources.first
    "#{card.brand} ××#{card.last4[-2..-1]}"
  end

  def update_plan(plan_id, trial_end)
    subscription.trial_end = if trial_end.future?
      trial_end.to_i
    else
      "now"
    end
    subscription.plan = plan_id
    subscription.save
  end

  def subscription
    @subscription ||= customer.subscriptions.first
  end

  private

  # `invoice_settings` isn't part of the customer shape at the pinned API
  # version, so `customer` never carries it — re-read at a version that does.
  def default_payment_method_card
    options = {stripe_version: STRIPE_INTENTS_API_VERSION}
    invoice_settings = Stripe::Customer.retrieve(id, options)[:invoice_settings]
    payment_method_id = invoice_settings && invoice_settings[:default_payment_method]
    return nil if payment_method_id.blank?
    Stripe::PaymentMethod.retrieve(payment_method_id, options).card
  end
end
