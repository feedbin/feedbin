class Throttle
  def self.throttle!(key, limit, period, &block)
    key = "#{key}:throttle"

    count, expiration = Sidekiq.redis do |client|
      client.multi do |transaction|
        transaction.incr key
        transaction.ttl key
      end
    end

    Sidekiq.redis { _1.expire(key, period.to_i) } if expiration == -1

    if count <= limit
      block_given? ? yield : true
    else
      false
    end
  end
end
