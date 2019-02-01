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
    invoice = Stripe::Invoice.all(customer: id, limit: 1).first
    if !invoice.paid && invoice.closed
      invoice.closed = false
      invoice.save
    elsif !invoice.paid && invoice.attempt_count >= 4
      invoice.pay
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
    @subscription ||= customer.subscriptions.first
  end
end
