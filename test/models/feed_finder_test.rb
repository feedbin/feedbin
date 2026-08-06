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

  # 127.0.0.1 reaches the real socket layer because WebMock is configured with
  # allow_localhost, so this exercises the guard rather than a stub. Unguarded,
  # the same call raises Feedkit::ConnectionError instead.
  test "refuses to discover a feed at a private address" do
    assert_raises Feedkit::PrivateNetworkAddress do
      FeedFinder.new("http://127.0.0.1:9/").response
    end
  end
end
