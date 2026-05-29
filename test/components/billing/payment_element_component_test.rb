require "test_helper"

class Billing::PaymentElementComponentTest < ComponentTestCase
  test "renders a form wired to the billing controller with the payment element and submit button" do
    html = render(Billing::PaymentElementComponent.new(
      publishable_key: "pk_test_1", mode: "setup", amount: 0, currency: "usd",
      endpoint: "/settings/billing/update_credit_card", return_url: "https://feedbin.com/back",
      submit_label: "Update"
    )).to_s

    assert_includes html, 'data-controller="billing"'
    assert_includes html, 'data-billing-publishable-key-value="pk_test_1"'
    assert_includes html, 'data-billing-mode-value="setup"'
    assert_includes html, 'data-action="submit->billing#submit"'  # the data-action attribute (rendered unescaped)
    assert_includes html, 'data-billing-target="paymentElement"'
    assert_includes html, 'data-billing-target="submit"'
    assert_includes html, "Update"
  end

  test "yields above-element content inside the form" do
    component = Billing::PaymentElementComponent.new(
      publishable_key: "pk_test_1", mode: "payment", amount: 5000, currency: "usd",
      endpoint: "/x", return_url: "/y", submit_label: "Subscribe"
    )
    html = render(component) { "PLAN_SELECTOR_SLOT" }.to_s
    assert_includes html, "PLAN_SELECTOR_SLOT"
    # slot content must appear BEFORE the payment-element mount
    assert html.index("PLAN_SELECTOR_SLOT") < html.index('id="payment-element"'), "yielded content should render above the mount"
  end
end
