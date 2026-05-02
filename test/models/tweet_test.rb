require "test_helper"

class TweetTest < ActiveSupport::TestCase
  def make_tweet(option: "one", overrides: {}, image: nil)
    tweet_data = load_tweet(option)
    tweet_data.merge!(overrides)
    Tweet.new({"tweet" => tweet_data}, image)
  end

  test "main_tweet returns the wrapped tweet when not a retweet" do
    tweet = make_tweet
    assert_equal tweet.tweet, tweet.main_tweet
  end

  test "main_tweet returns retweeted_status when present" do
    base = load_tweet("one")
    base.delete("quoted_status")
    base["retweeted_status"] = base.merge("id" => 12345, "full_text" => "Original")
    base["retweeted_status"]["entities"] = base["entities"]
    tweet = Tweet.new({"tweet" => base}, nil)
    assert tweet.tweet.retweeted_status?
    assert_equal 12345, tweet.main_tweet.id
  end

  test "retweet? mirrors tweet.retweeted_status?" do
    tweet = make_tweet
    refute tweet.retweet?
  end

  test "method_missing forwards to underlying Twitter::Tweet" do
    tweet = make_tweet
    assert_equal tweet.tweet.id, tweet.id
  end

  test "tweet_summary returns visible-text portion of the tweet" do
    tweet = make_tweet
    summary = tweet.tweet_summary
    assert_kind_of String, summary
    assert summary.length > 0
  end

  test "tweet_text returns auto-linked HTML when entities are present" do
    tweet = make_tweet
    text = tweet.tweet_text(tweet.main_tweet)
    assert_kind_of String, text
    assert text.length > 0
  end

  test "tweet_text falls back to full_text when entities are missing" do
    raw = load_tweet("one")
    raw.delete("entities")
    raw.delete("quoted_status")
    twitter = Twitter::Tweet.new(raw.deep_symbolize_keys)
    tweet = make_tweet
    text = tweet.tweet_text(twitter)
    assert_equal raw["full_text"], text.strip
  end

  test "twitter_media? returns true when media is present on main tweet" do
    tweet = make_tweet
    tweet.main_tweet.stub :media?, true do
      assert tweet.twitter_media?
    end
  end

  test "twitter_media? returns true when an external (non-twitter.com) URL is present" do
    raw = load_tweet("one")
    raw.delete("quoted_status")
    raw["entities"]["urls"] = [{
      "display_url" => "example.com",
      "indices" => [0, 10],
      "url" => "https://t.co/abc",
      "expanded_url" => "https://example.com/article"
    }]
    tweet = Tweet.new({"tweet" => raw}, nil)
    tweet.main_tweet.stub :media?, false do
      assert tweet.twitter_media?
    end
  end

  test "twitter_media? returns false when there are no urls and no media" do
    raw = load_tweet("one")
    raw.delete("quoted_status")
    raw["entities"]["urls"] = []
    tweet = Tweet.new({"tweet" => raw}, nil)
    tweet.main_tweet.stub :media?, false do
      refute tweet.twitter_media?
    end
  end

  test "link_tweet? is false when main tweet has a quoted status" do
    tweet = make_tweet
    tweet.main_tweet.stub :quoted_status?, true do
      refute tweet.link_tweet?
    end
  end

  test "link_tweet? is true when main tweet has exactly one url and no quoted status" do
    tweet = make_tweet
    fake_url = OpenStruct.new
    tweet.main_tweet.stub :quoted_status?, false do
      tweet.main_tweet.stub :urls, [fake_url] do
        assert tweet.link_tweet?
      end
    end
  end

  test "link_preview? returns false when image is set" do
    tweet = make_tweet(image: "/img.png")
    refute tweet.link_preview?
  end

  test "link_preview? returns false when not a link tweet" do
    tweet = make_tweet
    tweet.stub :link_tweet?, false do
      refute tweet.link_preview?
    end
  end

  test "link_preview? returns false when saved_pages has an error" do
    fake_url = OpenStruct.new(expanded_url: URI.parse("https://example.com/p"), indices: [0, 10])
    tweet = make_tweet
    tweet.main_tweet.stub :urls, [fake_url] do
      tweet.stub :link_tweet?, true do
        tweet.data.merge!(
          "saved_pages" => {"https://example.com/p" => {"result" => {"error" => "boom"}}},
          "twitter_link_image_processed" => "x"
        )
        refute tweet.link_preview?
      end
    end
  end

  test "link_preview? returns true with a valid saved_pages entry and processed link image" do
    fake_url = OpenStruct.new(expanded_url: URI.parse("https://example.com/p"), indices: [0, 10])
    tweet = make_tweet
    tweet.main_tweet.stub :urls, [fake_url] do
      tweet.stub :link_tweet?, true do
        tweet.data.merge!(
          "saved_pages" => {"https://example.com/p" => {"result" => {"ok" => true}}},
          "twitter_link_image_processed" => "x"
        )
        assert tweet.link_preview?
      end
    end
  end
end
