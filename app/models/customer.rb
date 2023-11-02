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
      trial_end: trial_end.to_i,
      payment_behavior: "default_incomplete",
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

  def update_source(stripe_token)
    customer.source = stripe_token
    customer.save
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
    @subscription ||= begin
      Stripe::Subscription.retrieve(
        id: customer.subscriptions.first.id,
        expand: ["latest_invoice.payment_intent", "pending_setup_intent"]
      )
    end
  end

  def subscription
    @subscription ||= begin
      Stripe::Subscription.retrieve(
        id: customer.subscriptions.first.id,
        expand: ["latest_invoice.payment_intent", "pending_setup_intent"]
      )
    end
  end
end