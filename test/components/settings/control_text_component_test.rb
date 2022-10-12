require "test_helper"

class Settings::ControlTextComponentTest < ViewComponent::TestCase
  def test_render_preview
    render_preview(:default)
    assert_text("Title")
    assert_text("Description")
    assert_selector("a", text: "Details")
  end
end
