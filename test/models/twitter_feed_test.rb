require 'test_helper'
class TwitterOptionsTest < ActiveSupport::TestCase

  test "should recognize user URLS" do
    url = "https://twitter.com/bsaid"
    twitter_feed = TwitterFeed.new(url, nil, nil)
    assert_equal "bsaid", twitter_feed.user
  end

  test "should recognize @user" do
    url = "@bsaid"
    twitter_feed = TwitterFeed.new(url, nil, nil)
    assert_equal "bsaid", twitter_feed.user
  end

  test "should recognize search urls" do
    url = "https://twitter.com/search?q=feedbin+ben&src=typd"
    twitter_feed = TwitterFeed.new(url, nil, nil)
    assert_equal "feedbin ben", twitter_feed.search
  end

  test "should recognize list urls" do
    url = "https://twitter.com/bsaid/lists/conversationlist"
    twitter_feed = TwitterFeed.new(url, nil, nil)
    result = {user: "bsaid", list: "conversationlist"}
    assert_equal result, twitter_feed.list
  end

  test "should recognize hashtag urls" do
    url = "https://twitter.com/hashtag/feedbin?src=hash"
    twitter_feed = TwitterFeed.new(url, nil, nil)
    assert_equal "#feedbin", twitter_feed.hashtag
  end

  test "should recognize hashtags" do
    url = "#feedbin"
    twitter_feed = TwitterFeed.new(url, nil, nil)
    assert_equal "#feedbin", twitter_feed.hashtag
  end
end
