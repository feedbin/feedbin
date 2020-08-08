require "test_helper"

class BodyLinksTest < ActiveSupport::TestCase
  test "should find candidate links" do
    url = "https://example.com"
    types = ["feed", "xml", "rss", "atom"]

    markup = types.each_with_object([]) do |type, array|
      stub_request_file("atom.xml", "#{url}/#{type}")
      array.push %(<a href="/#{type}">RSS</a>)
    end

    stub_request(:get, url).to_return(body: markup.join("\n"))

    response = Feedkit::Request.download(url)
    assert_difference "Feed.count", +4 do
      Source::BodyLinks.find(response)
    end
  end

  test "should skip html links" do
    url = "https://example.com"
    types = ["feed", "xml", "rss", "atom"]

    stub_request(:get, url).to_return(body: %(<a href="/rss">RSS</a>))
    stub_request_file("index.html", "#{url}/rss")

    response = Feedkit::Request.download(url)
    assert_no_difference "Feed.count", +4 do
      Source::BodyLinks.find(response)
    end
  end
end
