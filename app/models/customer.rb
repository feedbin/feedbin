# wraps a Stripe::Customer instance
class Customer
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

  def initialize(customer)
    @customer = customer
  end

  def unpaid?
    customer.try(:subscriptions).try(:first).try(:status) == "unpaid"
  end

  def reopen_account
    invoice = Stripe::Invoice.list(customer: id, limit: 1).first
    if !invoice.paid && invoice.closed && invoice.status != "draft"
      invoice.closed = false
      invoice.save
    elsif (!invoice.paid && invoice.attempt_count >= 4) || invoice.status == "draft"
      Stripe::Subscription.update(invoice.subscription,
        {
          billing_cycle_anchor: "now",
          proration_behavior: "none"
        }
      )
    end
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
