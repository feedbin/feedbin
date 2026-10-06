require "test_helper"

module FeedCrawler
  class CacheTest < ActiveSupport::TestCase
    def setup
      flush_redis
    end

    def test_should_delete
      cache_key = "cache_key"
      Cache.write(cache_key, {key: "value"})
      assert_equal({key: "value"}, Cache.read(cache_key))
      Cache.delete(cache_key)
      assert_equal({}, Cache.read(cache_key))
    end

    def test_should_increment
      assert_equal(1, Cache.increment("cache_key"))
    end

    def test_should_cache_values
      cache_key = "cache_key"
      Cache.write(cache_key, {
        etag: nil,
        last_modified: "last_modified",
      })

      values = Cache.read(cache_key)

      assert_equal("last_modified", values[:last_modified])
      assert_nil(values[:etag])
    end

    def test_should_cache_values_with_exiration
      cache_key = "cache_key"

      Cache.write(cache_key, {
          key: "value",
        },
        options: {expires_in: 1}
      )

      result = Sidekiq.redis do |redis|
        redis.ttl(cache_key)
      end

      assert_equal(1, result)
    end
  end
end