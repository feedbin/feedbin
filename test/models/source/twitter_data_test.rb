require "test_helper"

class TwitterDataTest < ActiveSupport::TestCase
  test "should find twitter feed" do
    feed = Feed.create!(feed_url: "https://twitter.com/feedbin?screen_name=screen_name")

    stub_request(:get, "https://api.twitter.com/1.1/statuses/user_timeline.json?count=100&exclude_replies=false&screen_name=feedbin&tweet_mode=extended")
      .to_return(status: 200, body: "", headers: {})

    auth = TwitterAuth.new(screen_name: "screen_name", token: "token", secret: "secret")
    feeds = Source::TwitterData.find("https://twitter.com/feedbin", auth)

    assert_equal(feed, feeds.first)
  end
end
