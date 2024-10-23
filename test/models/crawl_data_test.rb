require "test_helper"

class CrawlDataTest < ActiveSupport::TestCase

  def setup
    flush_redis
    @feed = feeds(:daring_fireball)
  end

  def test_should_be_ok
    feed = CrawlData.new
    feed.download_error(Exception.new)

    feed = CrawlData.new
    feed.download_success(@feed.id)

    feed = CrawlData.new
    assert feed.ok?(@feed.feed_url)
  end

  def test_should_not_be_ok
    feed = CrawlData.new
    feed.download_error(Feedkit::NotFeed.new)

    feed = CrawlData.new(feed.to_h)
    feed.download_success(@feed.id)

    feed = CrawlData.new(feed.to_h)
    assert_equal("Feedkit::NotFeed", feed.last_error["class"])
    refute feed.ok?(@feed.feed_url)
  end

  def test_retry_after_number
    retry_after = 1000
    time = Time.now.to_i + retry_after

    exception = http_exception_mock(retry_after)

    feed = CrawlData.new
    feed.download_error(exception)

    assert_equal(time, feed.last_error["retry_after"])
  end

  def test_retry_after_date
    feed = CrawlData.new

    retry_after = 2.hours.from_now
    exception = http_exception_mock(retry_after.httpdate)

    feed.download_error(exception)

    assert_equal(retry_after.to_i, feed.last_error["retry_after"])
  end

  def test_retry_after_max
    feed = CrawlData.new

    retry_after = 9.hours.from_now
    max_time = 8.hours.from_now

    exception = http_exception_mock(retry_after.to_i)

    feed.download_error(exception)

    assert_equal(max_time.to_i, feed.last_error["retry_after"])
  end

  def http_exception_mock(retry_after)
    OpenStruct.new({
      response: OpenStruct.new({
        status: OpenStruct.new({
          code: 429
        }),
        headers: {
          retry_after: " #{retry_after} "
        }
      })
    })
  end
end
