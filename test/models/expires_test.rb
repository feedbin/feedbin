require "test_helper"

class ExpiresTest < ActiveSupport::TestCase
  test "expires_in returns the future unix timestamp" do
    travel_to Time.utc(2026, 1, 1, 0, 0, 0) do
      assert_equal Time.utc(2026, 1, 1, 0, 5, 0).to_i, Expires.expires_in(5.minutes)
    end
  end

  test "expired? returns false for a future timestamp" do
    refute Expires.expired?(1.hour.from_now.to_i)
  end

  test "expired? returns true for a past timestamp" do
    assert Expires.expired?(1.hour.ago.to_i)
  end

  test "expired? returns false for nil" do
    refute Expires.expired?(nil)
  end
end
