require "test_helper"
module ImageCrawler
  class MetaImagesCacheTest < ActiveSupport::TestCase
    def setup
      flush_redis
    end

    def test_should_save_urls
      urls = ["one", "two"]
      cache = MetaImagesCache.new(Addressable::URI.parse("http://example.com/article"))
      cache.save({checked: true, urls: urls})

      assert_equal(urls, cache.urls)
    end

    def test_should_save_checked_status
      cache = MetaImagesCache.new(Addressable::URI.parse("http://example.com/article"))
      refute cache.checked?

      cache.save({checked: true, urls: []})
      assert cache.checked?
    end

    def test_has_meta_defaults_to_true
      cache = MetaImagesCache.new(Addressable::URI.parse("http://example.com/article"))
      assert cache.has_meta?
    end

    def test_has_meta_stays_true_below_failure_threshold
      url = Addressable::URI.parse("http://example.com/article")
      (MetaImagesCache::FAILURE_THRESHOLD - 1).times do
        MetaImagesCache.new(url).has_meta!(false)
      end
      assert MetaImagesCache.new(url).has_meta?
    end

    def test_has_meta_becomes_false_at_failure_threshold
      url = Addressable::URI.parse("http://example.com/article")
      MetaImagesCache::FAILURE_THRESHOLD.times do
        MetaImagesCache.new(url).has_meta!(false)
      end
      refute MetaImagesCache.new(url).has_meta?
    end

    def test_has_meta_false_expires
      url = Addressable::URI.parse("http://example.com/article")
      MetaImagesCache::FAILURE_THRESHOLD.times do
        MetaImagesCache.new(url).has_meta!(false)
      end
      cache = MetaImagesCache.new(url)
      ttl = Sidekiq.redis { |redis| redis.ttl(cache.host_cache_key) }
      assert_operator(ttl, :>, 0)
    end

    def test_has_meta_true_is_sticky
      url = Addressable::URI.parse("http://example.com/article")
      MetaImagesCache.new(url).has_meta!(true)

      MetaImagesCache::FAILURE_THRESHOLD.times do
        MetaImagesCache.new(url).has_meta!(false)
      end

      assert MetaImagesCache.new(url).has_meta?
    end

    def test_has_meta_true_has_no_expiry
      cache = MetaImagesCache.new(Addressable::URI.parse("http://example.com/article"))
      cache.has_meta!(true)
      ttl = Sidekiq.redis { |redis| redis.ttl(cache.host_cache_key) }
      assert_equal(-1, ttl)
    end

    def test_success_resets_failure_count
      url = Addressable::URI.parse("http://example.com/article")
      (MetaImagesCache::FAILURE_THRESHOLD - 1).times do
        MetaImagesCache.new(url).has_meta!(false)
      end

      cache = MetaImagesCache.new(url)
      count = Sidekiq.redis { |redis| redis.get(cache.failure_count_key) }
      assert_equal MetaImagesCache::FAILURE_THRESHOLD - 1, count.to_i

      MetaImagesCache.new(url).has_meta!(true)
      count = Sidekiq.redis { |redis| redis.get(cache.failure_count_key) }
      assert_nil count
    end
  end
end