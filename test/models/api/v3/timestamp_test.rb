require "test_helper"

class Api::V3::TimestampTest < ActiveSupport::TestCase
  test "parses an RFC 3339 time with an offset" do
    assert_equal Time.utc(2026, 11, 2, 10), Api::V3::Timestamp.parse("2026-11-02T10:00:00Z")
    assert_equal Time.utc(2026, 11, 2, 10, 0, 0.5r), Api::V3::Timestamp.parse("2026-11-02T05:00:00.5-05:00")
  end

  test "a time without an offset, or not a time, is nil" do
    assert_nil Api::V3::Timestamp.parse("2026-11-02T10:00:00")
    assert_nil Api::V3::Timestamp.parse("yesterday")
    assert_nil Api::V3::Timestamp.parse(nil)
    assert_nil Api::V3::Timestamp.parse("2026-13-45T10:00:00Z")
  end
end
