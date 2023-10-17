class RedisLock
  def self.acquire(lock_name, expiration_in_seconds = 55)
    Sidekiq.redis { _1.set(lock_name, "locked", ex: expiration_in_seconds, nx: true) }
  end
end
