# frozen_string_literal: true

class Cache
  def self.read(*args)
    new.read(*args)
  end

  def self.delete(*args)
    new.delete(*args)
  end

  def self.increment(key, **args)
    new.increment(key, **args)
  end

  def self.count(*args)
    new.count(*args)
  end

  def self.write(key, value, **args)
    new.write(key, value, **args)
  end

  def read(key)
    @read ||= begin
      value = Sidekiq.redis do |redis|
        redis.get key
      end
      JSON.load(value)&.transform_keys(&:to_sym) || {}
    end
  end

  def write(key, values, options: {})
    values = values.compact
    unless values.empty?
      Sidekiq.redis do |redis|
        redis.set(key, JSON.dump(values))
      end
    end
    write_key_expiry(key, options)
  end

  def delete(*keys)
    Sidekiq.redis { |redis| redis.unlink(*keys) }
  end

  def increment(key, options: {})
    count = Sidekiq.redis { |redis| redis.incr(key) }
    write_key_expiry(key, options)
    count
  end

  def count(key)
    Sidekiq.redis { |redis| redis.get(key) }.to_i
  end

  def write_key_expiry(key, options)
    if options[:expires_in]
      Sidekiq.redis do |redis|
        redis.expire key, options[:expires_in]
      end
    end
  end
end
