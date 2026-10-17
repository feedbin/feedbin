require "test_helper"

class FeedFinderTest < ActiveSupport::TestCase
  test "upstream Feedkit error is swallowed without notifying" do
    url = "http://upstream-fails.example.com/"
    stub_request(:get, url).to_return(status: 429)

    notified = []
    ErrorService.stub(:notify, ->(exception, *) { notified << exception }) do
      result = FeedFinder.feeds(url)
      assert_equal [], result, "expected empty feeds when upstream fails"
    end

    assert_empty notified, "expected upstream Feedkit errors not to be reported"
  end

  test "discovery falls through to the later strategies when the body is not markup" do
    url = "https://guessable.example.com/"
    stub_request(:get, url).to_return(body: "ok", headers: {"Content-Type" => "text/plain"})
    stub_request(:get, "#{url}feed").to_return(status: 404)
    stub_request_file("atom.xml", "#{url}rss")

    assert_difference "Feed.count", +1 do
      FeedFinder.feeds(url)
    end
  end

  test "unexpected (non-Feedkit) errors are still notified" do
    url = "http://boom.example.com/"
    stub_request(:get, url).to_return(status: 200, body: "ok")

    notified = []
    boom = RuntimeError.new("unexpected")
    # Force a non-Feedkit failure during source resolution.
    Source::ExistingFeed.stub(:find, ->(*) { raise boom }) do
      ErrorService.stub(:notify, ->(exception, *) { notified << exception }) do
        result = FeedFinder.feeds(url)
        assert_equal [], result
      end
    end

    assert_equal [boom], notified, "expected genuine bugs to still be reported"
  end

  test "a known feed downloaded in the last day is returned without downloading it again" do
    feed = feeds(:daring_fireball)
    feed.update!(crawl_data: {downloaded_at: 1.hour.ago.to_i})

    assert_equal [feed], FeedFinder.feeds(feed.feed_url)
    assert_not_requested :get, feed.feed_url
  end

  test "a known feed last downloaded over a day ago is downloaded" do
    feed = feeds(:daring_fireball)
    feed.update!(crawl_data: {downloaded_at: 2.days.ago.to_i})
    stub_request_file("atom.xml", feed.feed_url)

    FeedFinder.feeds(feed.feed_url)
    assert_requested :get, feed.feed_url
  end

  # So subscribing to a broken feed still answers not found
  test "a known feed whose last download failed is downloaded" do
    feed = feeds(:daring_fireball)
    feed.update!(crawl_data: {downloaded_at: 1.hour.ago.to_i, error_count: 1})
    stub_request(:get, feed.feed_url).to_return(status: 404)

    assert_equal [], FeedFinder.feeds(feed.feed_url)
    assert_requested :get, feed.feed_url
  end

  # crawl_error_message dates the crawler's error with downloaded_at
  test "a failing feed FeedFinder refreshes keeps the crawler's download time" do
    feed = feeds(:daring_fireball)
    crawled_at = 2.days.ago.to_i
    feed.update!(crawl_data: {downloaded_at: crawled_at, error_count: 1})
    stub_request_file("atom.xml", feed.feed_url)

    FeedFinder.feeds(feed.feed_url)
    assert_equal crawled_at, feed.reload.crawl_data.downloaded_at
  end

  test "a new feed FeedFinder downloads is not downloaded again within a day" do
    url = "https://new-feed.example.com/feed.xml"
    stub_request_file("atom.xml", url)

    first = FeedFinder.feeds(url)
    assert_equal first, FeedFinder.feeds(url)
    assert_requested :get, url, times: 1
  end

  test "a stale feed FeedFinder refreshes is not downloaded again within a day" do
    feed = feeds(:daring_fireball)
    feed.update!(crawl_data: {downloaded_at: 2.days.ago.to_i})
    stub_request_file("atom.xml", feed.feed_url)

    FeedFinder.feeds(feed.feed_url)
    assert_equal [feed], FeedFinder.feeds(feed.feed_url)
    assert_requested :get, feed.feed_url, times: 1
  end

  # 127.0.0.1 reaches the real socket layer because WebMock is configured with
  # allow_localhost, so this exercises the guard rather than a stub. Unguarded,
  # the same call raises Feedkit::ConnectionError instead.
  test "refuses to discover a feed at a private address" do
    assert_raises Feedkit::PrivateNetworkAddress do
      FeedFinder.new("http://127.0.0.1:9/").response
    end
  end
end
