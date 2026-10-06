require "test_helper"

class FontTest < ActiveSupport::TestCase
  test "stores name and slug" do
    font = Font.new("Helvetica", "helvetica")
    assert_equal "Helvetica", font.name
    assert_equal "helvetica", font.slug
  end
end
