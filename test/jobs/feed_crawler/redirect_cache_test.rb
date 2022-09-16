require "test_helper"

module Crawler
  module Refresher
    class RedirectCacheTest < ActiveSupport::TestCase

      def setup
        flush_redis
      end

      def test_should_collapse_stable_redirects
        feed_id = 2

        redirect1 = RedirectCache::Redirect.new(feed_id, status: 301, from: "http://example.com", to: "http://example.com/second")
        redirect2 = RedirectCache::Redirect.new(feed_id, status: 301, from: "http://example.com/second", to: "http://example.com/third")
        redirect3 = RedirectCache::Redirect.new(feed_id, status: 301, from: "http://example.com/third", to: "http://example.com/final")

        (RedirectCache::PERSIST_AFTER).times do
          RedirectCache.new(feed_id).save([redirect1, redirect2])
        end

        assert_nil RedirectCache.new(feed_id).read

        RedirectCache.new(feed_id).save([redirect1, redirect2])

        assert_equal(redirect2.to, RedirectCache.new(feed_id).read)

        (RedirectCache::PERSIST_AFTER + 1).times do
          RedirectCache.new(feed_id).save([redirect2, redirect3])
        end

        assert_equal(redirect3.to, RedirectCache.new(feed_id).read)
      end

      def test_should_not_temporary_redirects
        redirect1 = RedirectCache::Redirect.new(1, status: 302, from: "http://example.com", to: "http://example.com/second")
        assert_nil RedirectCache.new(1).save([redirect1])
      end

      def test_should_not_save_empty_redirects
        assert_nil RedirectCache.new(1).save([])
      end
    end
  end
end