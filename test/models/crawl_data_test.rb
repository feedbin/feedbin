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
    retry_after = 10_000
    time = Time.now.to_i + retry_after

    exception = http_exception_mock(retry_after)

    feed = CrawlData.new
    feed.download_error(exception)

    assert_equal(time, feed.retry_after)
  end

  def test_retry_after_date
    feed = CrawlData.new

    retry_after = 2.hours.from_now
    exception = http_exception_mock(retry_after.httpdate)

    feed.download_error(exception)

    assert_equal(retry_after.to_i, feed.retry_after)
  end

  def test_retry_after_max
    feed = CrawlData.new

    retry_after = 9.hours.from_now
    max_time = 8.hours.from_now

    exception = http_exception_mock(retry_after.to_i)

    feed.download_error(exception)

    assert_equal(max_time.to_i, feed.retry_after)
  end

  def test_save_should_keep_validators_when_not_modified
    url = "http://example.com/atom.xml"
    stub_request(:get, url).to_return(status: 304)

    data = CrawlData.new({
      etag: "etag",
      last_modified: "last_modified",
      download_fingerprint: "694b08e"
    })

    data.save(Feedkit::Request.download(url))

    assert_equal("etag", data.etag)
    assert_equal("last_modified", data.last_modified)
    assert_equal("694b08e", data.download_fingerprint)
  end

  def test_save_should_use_validators_supplied_by_not_modified
    url = "http://example.com/atom.xml"
    stub_request(:get, url).to_return(status: 304, headers: {
      "Etag" => "new_etag",
      "Last-Modified" => "new_last_modified"
    })

    data = CrawlData.new({
      etag: "etag",
      last_modified: "last_modified",
      download_fingerprint: "694b08e"
    })

    data.save(Feedkit::Request.download(url))

    assert_equal("new_etag", data.etag)
    assert_equal("new_last_modified", data.last_modified)
    assert_equal("694b08e", data.download_fingerprint)
  end

  def test_save_should_clear_validators_the_server_stopped_sending
    url = "http://example.com/atom.xml"
    stub_request(:get, url).to_return(status: 200, body: "body")

    data = CrawlData.new({
      etag: "etag",
      last_modified: "last_modified",
      download_fingerprint: "694b08e"
    })

    data.save(Feedkit::Request.download(url))

    assert_nil(data.etag)
    assert_nil(data.last_modified)
    assert_equal(Digest::SHA1.hexdigest("body")[0, 7], data.download_fingerprint)
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
