require "test_helper"

class GuessTest < ActiveSupport::TestCase
  test "should guess /feed" do
    url = "https://example.com"
    stub_request(:get, url)
    stub_request(:get, "#{url}/rss").to_return(status: 404)
    stub_request_file("atom.xml", "#{url}/feed")
    response = Feedkit::Request.download(url)
    assert_difference "Feed.count", +1 do
      Source::Guess.find(response)
    end
  end

  test "should guess /rss" do
    url = "https://example.com"
    stub_request(:get, url)
    stub_request(:get, "#{url}/feed").to_return(status: 404)
    stub_request_file("atom.xml", "#{url}/rss")
    response = Feedkit::Request.download(url)
    assert_difference "Feed.count", +1 do
      Source::Guess.find(response)
    end
  end
end
