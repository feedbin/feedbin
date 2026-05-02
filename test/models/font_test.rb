require "test_helper"

class FontTest < ActiveSupport::TestCase
  test "stores name and slug" do
    font = Font.new("Helvetica", "helvetica")
    assert_equal "Helvetica", font.name
    assert_equal "helvetica", font.slug
  end

  test "name and slug are writable" do
    font = Font.new("Old", "old")
    font.name = "New"
    font.slug = "new"
    assert_equal "New", font.name
    assert_equal "new", font.slug
  end
end
