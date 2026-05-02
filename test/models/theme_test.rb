require "test_helper"

class ThemeTest < ActiveSupport::TestCase
  test "stores name and slug" do
    theme = Theme.new("Dusk", "dusk")
    assert_equal "Dusk", theme.name
    assert_equal "dusk", theme.slug
  end

  test "name and slug are writable" do
    theme = Theme.new("Old", "old")
    theme.name = "New"
    theme.slug = "new"
    assert_equal "New", theme.name
    assert_equal "new", theme.slug
  end
end
