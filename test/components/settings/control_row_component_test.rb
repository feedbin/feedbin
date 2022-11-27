require "test_helper"

class Settings::ControlRowComponentTest < ViewComponent::TestCase
  def test_render_preview
    render_preview(:default)
    assert_text("Title")
    assert_text("Description")
    assert_selector("div", text: "Details")
  end
end
