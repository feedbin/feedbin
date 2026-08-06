class Tweet
  attr_accessor :tweet, :data

  def initialize(data, image)
    @image = image
    @data = data
    @tweet = Twitter::Tweet.new(data["tweet"].deep_symbolize_keys)
  end

  def main_tweet
    @main_tweet ||= tweet.retweeted_status? ? tweet.retweeted_status : tweet
  end

  def twitter_media?
    media = false
    tweets = [main_tweet]
    tweets.push(main_tweet.quoted_status) if main_tweet.quoted_status?

    media = tweets.find do |tweet|
      return true if tweet.media?
      urls = tweet.urls.reject { |url| url.expanded_url.host == "twitter.com" }
      return true unless urls.empty?
    rescue
      false
    end
    !!media
  end

  def retweet?
    tweet.retweeted_status?
  end

  def link_tweet?
    return false if main_tweet.quoted_status?
    main_tweet.urls.length == 1
  end

  def tweet_summary(tweet = nil, strip_trailing_link = false)
    tweet ||= main_tweet
    hash = tweet.to_h

    text = trim_text(hash, true)
    tweet.urls.reverse_each do |url|
      range = Range.new(*url.indices, true)
      if strip_trailing_link && strip_trailing_link?
        text[range] = ""
      else
        text[range] = url.display_url
      end
    rescue
    end
    text
  end

  def tweet_text(tweet, options = {})
    hash = tweet.to_h
    if hash[:entities]
      hash = remove_entities(hash)
      text = trim_text(hash, false, true)
      text = Twitter::TwitterText::Autolink.auto_link_with_json(text, hash[:entities], options).html_safe
    else
      text = hash[:full_text]
    end
    if text.respond_to?(:strip)
      text.strip
    else
      text
    end
  rescue
    hash[:full_text]
  end

  def link_preview?
    return false unless link_tweet?
    return false if @image.present?
    return false unless data.safe_dig("saved_pages", main_tweet.urls.first.expanded_url.to_s).present?
    return false if data.safe_dig("saved_pages", main_tweet.urls.first.expanded_url.to_s, "result", "error")
    data.safe_dig("twitter_link_image_processed").present?
  end

  private

  # dup on the branch that does not already build a new string: callers assign
  # into the result through entity index ranges, and without this that edited
  # the Twitter::Tweet's own full_text -- which is also its :text attribute.
  def trim_text(hash, exclude_end = false, trim_start = false)
    text = hash[:full_text]
    if range = hash[:display_text_range]
      start = trim_start ? range.first : 0
      range = Range.new(start, range.last, exclude_end)
      text.codepoints[range].pack("U*")
    else
      text.dup
    end
  end

  # tweet.to_h is the Twitter::Tweet's own attrs hash, not a copy, so editing it
  # here would prune the tweet's entities permanently and shift their indices
  # again on every later render. Build a new hash instead and leave the tweet
  # as it was found.
  def remove_entities(hash)
    return hash unless hash[:display_text_range]

    text_start = hash[:display_text_range].first
    text_end = hash[:display_text_range].last

    entities = hash[:entities].each_with_object({}) do |(entity, values), result|
      result[entity] = values.reject { |value|
        value[:indices].last < text_start || value[:indices].first > text_end
      }.map { |value|
        value.merge(indices: [
          value[:indices][0] - text_start,
          value[:indices][1] - text_start
        ])
      }
    end

    hash.merge(entities: entities)
  end

  def strip_trailing_link?
    hash = main_tweet.to_h
    link_preview? && main_tweet.urls.first.indices.last == hash[:full_text].length
  end

  def method_missing(*args, &block)
    tweet.public_send(*args, *block)
  end
end
