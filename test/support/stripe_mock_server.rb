# Points the Stripe gem at a locally-running stripe-mock instance for the test suite.
# test_helper.rb boots stripe-mock automatically (unless ENV["CI"], where it runs as
# a service container) and sets STRIPE_MOCK_HOST, so no manual startup is needed.
module StripeMockServer
  HOST = ENV.fetch("STRIPE_MOCK_HOST", "http://localhost:12111")

  def self.configure!
    Stripe.api_key = "sk_test_123"
    Stripe.api_base = HOST
    Stripe.connect_base = HOST
    Stripe.uploads_base = HOST
  end
end
