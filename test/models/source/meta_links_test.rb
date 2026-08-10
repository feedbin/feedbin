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

  test "options is empty when the body is not a parseable document" do
    url = "https://plaintext.example.com/"
    stub_request(:get, url).to_return(body: "ok", headers: {"Content-Type" => "text/plain"})
    response = Feedkit::Request.download(url)

    assert_equal [], Source::MetaLinks.options(response)
  end

  test "find is a no-op when the body is not a parseable document" do
    url = "https://plaintext.example.com/"
    stub_request(:get, url).to_return(body: "ok", headers: {"Content-Type" => "text/plain"})
    response = Feedkit::Request.download(url)

    assert_equal [], Source::MetaLinks.find(response)
  end

  test "should find json links" do
    url = "https://example.com"
    feed_url = "/feeds/json/"
    stub_request(:get, url)
      .to_return(body: %(<link rel="alternate" type="application/json" href="#{feed_url}"/>))
    stub_request_file("feed_single.json", url + feed_url)
    response = Feedkit::Request.download(url)
    assert_difference "Feed.count", +1 do
      Source::MetaLinks.find(response)
    end
  end
end
