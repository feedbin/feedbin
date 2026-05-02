require "test_helper"

class PushTest < ActiveSupport::TestCase
  test "hub_secret is a SHA1 hex digest" do
    secret = Push.hub_secret(42)
    assert_match(/\A[0-9a-f]{40}\z/, secret)
  end

  test "hub_secret is deterministic for the same feed_id" do
    assert_equal Push.hub_secret(42), Push.hub_secret(42)
  end

  test "hub_secret differs by feed_id" do
    refute_equal Push.hub_secret(42), Push.hub_secret(43)
  end
end
