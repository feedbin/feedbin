require "test_helper"

class KnownPatternTest < ActiveSupport::TestCase
  test "should recognize knows patterns" do
    urls = {
      "https://www.youtube.com/channel/abc"       => "https://www.youtube.com/feeds/videos.xml?channel_id=abc",
      "https://www.youtube.com/user/abc"          => "https://www.youtube.com/feeds/videos.xml?user=abc",
      "https://www.youtube.com/playlist?list=abc" => "https://www.youtube.com/feeds/videos.xml?playlist_id=abc",
      "https://www.reddit.com/r/abc"              => "https://www.reddit.com/r/abc.rss",
      "https://vimeo.com/abc"                     => "https://vimeo.com/abc/videos/rss"
    }
    urls.each do |known_pattern, destination|
      stub_request_file("index.html", known_pattern)
      stub_request_file("atom.xml", destination)
      response = Feedkit::Request.download(known_pattern)
      assert_difference "Feed.count", +1 do
        Source::KnownPattern.find(response)
      end
    end
  end

  test "should find channelId" do
    url = "https://www.youtube.com"
    channel_id = "abc"
    stub_request(:get, url)
      .to_return(
        body: <<~EOD
        <head>
          <meta itemprop="channelId" content="#{channel_id}">
        </head>
        EOD
      )
    stub_request_file("atom.xml", "https://www.youtube.com/feeds/videos.xml?channel_id=#{channel_id}")
    response = Feedkit::Request.download(url)
    assert_difference "Feed.count", +1 do
      Source::KnownPattern.find(response)
    end
  end
end
