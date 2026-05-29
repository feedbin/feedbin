# Points the Stripe gem at a locally-running stripe-mock instance for the test suite.
# Start stripe-mock before running tests:  stripe-mock -http-port 12111
module StripeMockServer
  HOST = ENV.fetch("STRIPE_MOCK_HOST", "http://localhost:12111")

  def self.configure!
    Stripe.api_key = "sk_test_123"
    Stripe.api_base = HOST
    Stripe.connect_base = HOST
    Stripe.uploads_base = HOST
  end
end
