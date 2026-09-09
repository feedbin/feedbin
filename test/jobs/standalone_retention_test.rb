require "test_helper"

class StandaloneRetentionTest < ActiveSupport::TestCase
  test "TTL is ninety days" do
    assert_equal 90.days, StandaloneRetention::TTL
  end
end
