require "test_helper"

class Billing::SubscribeFormComponentTest < ComponentTestCase
  test "renders plan radios and a payment-mode element for an immediate charge" do
    plan = plans(:basic_yearly_3)
    html = render(Billing::SubscribeFormComponent.new(
      publishable_key: "pk_test_1", plans: [plan], default_plan: plan,
      subscribe_title: "Plan", mode: "payment", user: users(:ben)
    )).to_s
    assert_includes html, 'data-billing-mode-value="payment"'
    assert_includes html, "Plan"
    assert_includes html, 'data-billing-target="planInput"'
    assert_includes html, "Subscribe"
    assert_includes html, "subscribe-description"
    assert_includes html, 'data-billing-target="planHelp"'
  end

  test "uses setup mode and zero amount for a future trial" do
    plan = plans(:basic_yearly_3)
    html = render(Billing::SubscribeFormComponent.new(
      publishable_key: "pk_test_1", plans: [plan], default_plan: plan,
      subscribe_title: "Plan", mode: "setup", user: users(:ben)
    )).to_s
    assert_includes html, 'data-billing-mode-value="setup"'
    assert_includes html, 'data-billing-amount-value="0"'
  end
end
