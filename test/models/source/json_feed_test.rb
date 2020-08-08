require "test_helper"

class JsonFeedTest < ActiveSupport::TestCase
  test "should create feed" do
    url = "https://example.com/feed.json"
    stub_request_file("feed.json", url)
    response = Feedkit::Request.download(url)
    assert_difference "Feed.count", +1 do
      Source::Xml.find(response)
    end
  end
end
