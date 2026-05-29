require "test_helper"

class UpdateStatementDescriptorTest < ActiveSupport::TestCase
  setup do
    @user = users(:ben)
  end

  test "Should update invoice" do
    event = stripe_webhook_event("invoice_created", customer: @user.customer_id)
    invoice_id = event["data"]["object"]["id"]

    stub_request(:post, "#{Stripe.api_base}/v1/invoices/#{invoice_id}")
      .to_raise(Stripe::APIError)

    billing_event = BillingEvent.create!(info: event)

    UpdateStatementDescriptor.new.perform(billing_event.id) rescue nil

    assert_requested(:post, "#{Stripe.api_base}/v1/invoices/#{invoice_id}") { _1.body == "statement_descriptor=Example%2C+Inc.+#{@user.id}" }
  end
end
