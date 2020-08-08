require "test_helper"

class MetaLinksTest < ActiveSupport::TestCase
  test "should find atom links" do
    url = "https://example.com"
    feed_url = "https://example2.com/comments/feed/"
    stub_request(:get, url)
      .to_return(body: %(<link rel="alternate" type="application/atom+xml" href="#{feed_url}"/>))
    stub_request_file("atom.xml", feed_url)
    response = Feedkit::Request.download(url)
    assert_difference "Feed.count", +1 do
      Source::MetaLinks.find(response)
    end
  end

  test "should find rss links" do
    url = "https://example.com"
    feed_url = "/comments/feed/"
    stub_request(:get, url)
      .to_return(body: %(<link rel="alternate" type="application/atom+xml" href="#{feed_url}"/>))
    stub_request_file("atom.xml", url + feed_url)
    response = Feedkit::Request.download(url)
    assert_difference "Feed.count", +1 do
      Source::MetaLinks.find(response)
    end
  end

  test "should find json links" do
    url = "https://example.com"
    feed_url = "/feeds/json/"
    stub_request(:get, url)
      .to_return(body: %(<link rel="alternate" type="application/json" href="#{feed_url}"/>))
    stub_request_file("feed.json", url + feed_url)
    response = Feedkit::Request.download(url)
    assert_difference "Feed.count", +1 do
      Source::MetaLinks.find(response)
    end
  end
end
