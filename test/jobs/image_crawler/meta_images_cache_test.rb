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

    def test_should_save_meta_presence
      cache = MetaImagesCache.new(Addressable::URI.parse("http://example.com/article"))
      assert cache.has_meta?

      cache.has_meta!(false)
      refute cache.has_meta?

      cache.has_meta!(true)
      assert cache.has_meta?
    end
  end
end