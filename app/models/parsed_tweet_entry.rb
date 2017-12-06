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
    @tweet.user.name || "@#{@tweet.user.name.screen_name}"
  end

  def content
    Twitter::Autolink.auto_link_with_json(to_h[:full_text], to_h[:extended_entities])
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

  def to_h
    @to_h ||= @tweet.to_h
  end

end
