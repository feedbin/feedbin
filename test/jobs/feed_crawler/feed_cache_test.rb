require "test_helper"

module FeedCrawler
  class FeedCacheTest < ActiveSupport::TestCase

    def setup
      flush_redis
    end

    def test_should_be_ok
      feed_id = 1
      feed = FeedCache.new(feed_id)
      feed.download_error(Exception.new)

      feed = FeedCache.new(feed_id)
      feed.download_success

      feed = FeedCache.new(feed_id)
      assert feed.ok?
    end

    def test_should_not_be_ok
      feed_id = 1
      feed = FeedCache.new(feed_id)
      feed.download_error(Feedkit::NotFeed.new)

      feed = FeedCache.new(feed_id)
      feed.download_success

      feed = FeedCache.new(feed_id)
      assert_equal("Feedkit::NotFeed", feed.last_error["class"])
      refute feed.ok?
    end
  end
end
