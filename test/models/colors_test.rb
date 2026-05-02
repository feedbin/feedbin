require "test_helper"

class ColorsTest < ActiveSupport::TestCase
  test "fetch returns the color for a known theme symbol" do
    assert_equal "#FFFFFF", Colors.fetch(:day)
    assert_equal "#000000", Colors.fetch(:midnight)
  end

  test "fetch returns the color for a known theme string" do
    assert_equal "#f5f2eb", Colors.fetch("sunset")
  end

  test "fetch falls back to day for an unknown theme" do
    assert_equal "#FFFFFF", Colors.fetch(:unknown)
  end
end
