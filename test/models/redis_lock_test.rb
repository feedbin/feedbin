require "test_helper"

class RedisLockTest < ActiveSupport::TestCase
  setup do
    flush_redis
    @lock_name = "test-lock-#{SecureRandom.hex(4)}"
  end

  test "acquire returns true the first time and false on subsequent attempts" do
    assert RedisLock.acquire(@lock_name)
    refute RedisLock.acquire(@lock_name)
  end

  test "acquire respects a custom expiration" do
    RedisLock.acquire(@lock_name, 120)

    ttl = Sidekiq.redis { |r| r.ttl(@lock_name) }
    assert_in_delta 120, ttl, 5
  end
end
