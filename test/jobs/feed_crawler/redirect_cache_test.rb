require "test_helper"

module FeedCrawler
  class RedirectCacheTest < ActiveSupport::TestCase

    def setup
      flush_redis
    end

    def test_should_collapse_stable_redirects
      feed_id = 2

      redirect1 = Feedkit::Redirect.new(status: 301, from: "http://example.com", to: "http://example.com/second")
      redirect2 = Feedkit::Redirect.new(status: 301, from: "http://example.com/second", to: "http://example.com/third")
      redirect3 = Feedkit::Redirect.new(status: 301, from: "http://example.com/third", to: "http://example.com/final")

      result_one = nil
      (RedirectCache::PERSIST_AFTER).times do
        result_one = RedirectCache.new(feed_id)
        result_one.save([redirect1, redirect2])
      end

      assert_nil RedirectCache.new(feed_id).read

      RedirectCache.new(feed_id).save([redirect1, redirect2])

      assert_equal(redirect2.to, RedirectCache.new(feed_id).read)

      result_two = nil
      (RedirectCache::PERSIST_AFTER + 1).times do
        result_two = RedirectCache.new(feed_id)
        result_two.save([redirect2, redirect3])
      end

      assert_equal(redirect3.to, RedirectCache.new(feed_id).read)

      assert_equal(result_one.counter_key, "refresher_redirect_tmp_339f281b1a0eb4047951da6be5f3dddf543fa486")
      assert_equal(result_two.counter_key, "refresher_redirect_tmp_a7cd95f3c54b3c08d5cd75b75a2ae057e78763cc")
    end

    def test_should_not_temporary_redirects
      redirect1 = Feedkit::Redirect.new(status: 302, from: "http://example.com", to: "http://example.com/second")
      assert_nil RedirectCache.new(1).save([redirect1])
    end

    def test_should_not_save_empty_redirects
      assert_nil RedirectCache.new(1).save([])
    end
  end
end