require "test_helper"

class Billing::UpdateCardComponentTest < ComponentTestCase
  test "renders an update form using the payment element in setup mode" do
    html = render(Billing::UpdateCardComponent.new(publishable_key: "pk_test_1")).to_s
    assert_includes html, 'data-billing-mode-value="setup"'
    assert_includes html, 'data-controller="billing"'
    assert_includes html, "Update"
  end
end
