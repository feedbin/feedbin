class RedisLock
  def self.acquire(lock_name, expiration_in_seconds = 55)
    !!Sidekiq.redis { _1.set(lock_name, "locked", "nx", "ex", expiration_in_seconds) }
  end
end
