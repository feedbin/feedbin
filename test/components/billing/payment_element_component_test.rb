require "test_helper"

class Billing::PaymentElementComponentTest < ComponentTestCase
  test "renders the mount point and wires the stimulus controller" do
    html = render(Billing::PaymentElementComponent.new(
      publishable_key: "pk_test_1", mode: "setup", amount: 0, currency: "usd",
      endpoint: "/settings/billing/update_credit_card", return_url: "https://feedbin.com/back"
    )).to_s
    assert_includes html, 'data-controller="billing"'
    assert_includes html, 'data-billing-publishable-key-value="pk_test_1"'
    assert_includes html, 'data-billing-mode-value="setup"'
    assert_includes html, 'data-billing-target="paymentElement"'
  end
end
