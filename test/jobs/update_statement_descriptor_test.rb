require "test_helper"

class UpdateStatementDescriptorTest < ActiveSupport::TestCase
  setup do
    @user = users(:ben)
  end

  test "Should update invoice" do
    StripeMock.start
    event = StripeMock.mock_webhook_event("invoice.created", {customer: @user.customer_id})
    StripeMock.stop

    stub_request(:post, "https://api.stripe.com/v1/invoices/in_00000000000000")
      .to_raise(Stripe::APIError)

    billing_event = BillingEvent.create!(info: event.as_json)

    UpdateStatementDescriptor.new.perform(billing_event.id) rescue nil

    assert_requested(:post, "https://api.stripe.com/v1/invoices/in_00000000000000") { _1.body == "statement_descriptor=Example%2C+Inc.+#{@user.id}" }
  end
end
