class Throttle
  def self.throttle!(key, limit, period, &block)
    key = "#{key}:v2"
    count = Rails.cache.increment(key, 1, expires_in: period.to_i, initial: 1)
    if count <= limit
      yield
    else
      false
    end
  end
end
