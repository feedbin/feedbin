module Billing
  # Wraps a Stripe::Customer using the modern API. Subscriptions are no longer
  # embedded on the customer object, so they are fetched on demand.
  class Customer
    attr_reader :customer
    delegate :id, :email, to: :customer

    def self.create(email:)
      new(Stripe::Customer.create(email: email))
    end

    def self.retrieve(customer_id)
      new(Stripe::Customer.retrieve(customer_id))
    end

    def initialize(customer)
      @customer = customer
    end

    def update_email(email)
      @customer = Stripe::Customer.update(id, email: email)
    end

    def subscription
      @subscription ||= Stripe::Subscription.list(customer: id, limit: 1).data.first
    end

    def unpaid?
      subscription&.status == "unpaid"
    end

    def cancel
      Stripe::Customer.delete(id)
    end
  end
end
