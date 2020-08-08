require "test_helper"

class ExistingFeedTest < ActiveSupport::TestCase
  test "should find existing feed" do
    url = "http://example.com/atom.xml"

    feed = Feed.create!(feed_url: url)

    stub_request_file("atom.xml", url)

    response = Feedkit::Request.download(url)

    feeds = Source::ExistingFeed.find(response)

    assert_equal(feed, feeds.first)
  end
end
