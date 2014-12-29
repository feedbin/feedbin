# wraps a Stripe::Customer instance
class Customer
  attr_reader :customer

  delegate :id, to: :customer

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
    if !invoice.paid && invoice.attempt_count >= 4
      if invoice.closed
        invoice.closed = false
        invoice.save
      end
      invoice.pay
    end
  end
end

