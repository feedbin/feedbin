Stripe.api_key = ENV['STRIPE_API_KEY']
Stripe.api_version = "2016-07-06"
STRIPE_PUBLIC_KEY = ENV['STRIPE_PUBLIC_KEY']

StripeEvent.setup do
  all do |event|
    BillingEvent.create(info: event.as_json)
  end
end