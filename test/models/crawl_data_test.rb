require "test_helper"

class CrawlDataTest < ActiveSupport::TestCase

  def setup
    flush_redis
  end

  def test_should_be_ok
    feed_id = 1
    feed = CrawlData.new
    feed.download_error(Exception.new)

    feed = CrawlData.new
    feed.download_success(feed_id)

    feed = CrawlData.new
    assert feed.ok?
  end

  def test_should_not_be_ok
    feed_id = 1
    feed = CrawlData.new
    feed.download_error(Feedkit::NotFeed.new)

    feed = CrawlData.new(feed.to_h)
    feed.download_success(feed_id)

    feed = CrawlData.new(feed.to_h)
    assert_equal("Feedkit::NotFeed", feed.last_error["class"])
    refute feed.ok?
  end
end
