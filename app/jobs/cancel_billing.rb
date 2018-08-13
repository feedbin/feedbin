class CancelBilling
  include Sidekiq::Worker
  sidekiq_options queue: :default

  def perform(customer_id)
    Honeybadger.context(customer_id: customer_id)
    customer = Stripe::Customer.retrieve(customer_id)
    customer.delete
  end
end
