Stripe.api_key = ENV['STRIPE_API_KEY']
STRIPE_PUBLIC_KEY = ENV['STRIPE_PUBLIC_KEY']

StripeEvent.setup do
  subscribe do |event|
    BillingEvent.create(details: event)
  end
end