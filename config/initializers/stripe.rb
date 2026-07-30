Stripe.api_key = ENV["STRIPE_API_KEY"]
Stripe.api_version = "2016-07-06"
StripeEvent.signing_secret = ENV["STRIPE_SIGNING_SECRET"]
STRIPE_PUBLIC_KEY = ENV["STRIPE_PUBLIC_KEY"]

# SetupIntents, PaymentMethods, and `customer.invoice_settings` all postdate the
# version pinned above, which has no concept of any of them. Requests that touch
# those resources pass this version explicitly instead, so they're validated and
# rendered against an API that has them. Everything else stays on 2016-07-06.
#
# Card-only is still the default for intents at this version, so no `return_url`
# or redirect handling is required for the Card Element flow.
STRIPE_INTENTS_API_VERSION = "2020-08-27"

StripeEvent.setup do
  all do |event|
    BillingEvent.create(info: event.as_json)
  end
end
