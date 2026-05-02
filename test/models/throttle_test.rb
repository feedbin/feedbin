require "test_helper"

class ThrottleTest < ActiveSupport::TestCase
  setup do
    flush_redis
    @key = "throttle-test-#{SecureRandom.hex(4)}"
  end

  test "returns true and yields the block while count is at or below the limit" do
    yielded = 0
    3.times do
      result = Throttle.throttle!(@key, 3, 60) { yielded += 1; :ran }
      assert_equal :ran, result
    end
    assert_equal 3, yielded
  end

  test "returns false once the limit is exceeded" do
    Throttle.throttle!(@key, 1, 60) { :ran }
    refute Throttle.throttle!(@key, 1, 60) { :ran }
  end

  test "returns true without a block when under the limit" do
    assert Throttle.throttle!(@key, 1, 60)
  end

  test "sets a TTL on the key the first time it is touched" do
    Throttle.throttle!(@key, 5, 90)
    ttl = Sidekiq.redis { |r| r.ttl("#{@key}:throttle") }
    assert_in_delta 90, ttl, 5
  end
end
