Stripe.api_key = ENV["STRIPE_API_KEY"]
Stripe.api_version = "2016-07-06"
StripeEvent.signing_secret = ENV["STRIPE_SIGNING_SECRET"]
STRIPE_PUBLIC_KEY = ENV["STRIPE_PUBLIC_KEY"]

StripeEvent.setup do
  all do |event|
    BillingEvent.create(info: event.as_json)
  end
end
