require "test_helper"

class Settings::BoxComponentTest < ViewComponent::TestCase
  def test_render_preview
    render_preview(:default)
    assert_text("Setting")
    assert_selector(".text-600", text: "Control")
  end
end
