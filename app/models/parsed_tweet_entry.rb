require 'socket'

class ParsedTweetEntry < ParsedEntry

  def initialize(tweet, feed_url)
    @tweet = tweet
    @feed_url = feed_url
  end

  def entry_id
    @tweet.id
  end

  def author
    main_tweet.user.name || "@#{main_tweet.user.name.screen_name}"
  end

  def content
    if tweet_hash[:entities]
      Twitter::TwitterText::Autolink.auto_link_with_json(tweet_hash[:full_text], tweet_hash[:entities]).html_safe
    else
      tweet_hash[:full_text]
    end
  end

  def data
    value = {}
    value["tweet"] = @tweet.to_h
    value
  end

  def published
    @tweet.created_at
  end

  def title
    nil
  end

  def url
    @tweet.url.to_s
  end

  def main_tweet
    (@tweet.retweeted_status?) ? @tweet.retweeted_status : @tweet
  end

  def tweet_hash
    @tweet_hash ||= main_tweet.to_h
  end

end
