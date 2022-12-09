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

  def tweet_link_image
    if data && data["twitter_link_image_processed"]
      image_url = data["twitter_link_image_processed"]

      host = ENV["ENTRY_IMAGE_HOST"]

      url = URI(image_url)
      url.host = host if host
      url.scheme = "https"
      url.to_s
    end
  end

  def tweet_link_image_placeholder_color
    if data && data["twitter_link_image_placeholder_color"].respond_to?(:length) && data["twitter_link_image_placeholder_color"].length == 6
      data["twitter_link_image_placeholder_color"]
    end
  end

  def link_preview?
    return false unless link_tweet?
    return false if @image.present?
    return false unless data.dig("saved_pages", main_tweet.urls.first.expanded_url.to_s).present?
    return false if data.dig("saved_pages", main_tweet.urls.first.expanded_url.to_s, "result", "error")
    data.dig("twitter_link_image_processed").present?
  end

  private

  def trim_text(hash, exclude_end = false, trim_start = false)
    text = hash[:full_text]
    if range = hash[:display_text_range]
      start = trim_start ? range.first : 0
      range = Range.new(start, range.last, exclude_end)
      text = text.codepoints[range].pack("U*")
    end
    text
  end

  def remove_entities(hash)
    if hash[:display_text_range]
      text_start = hash[:display_text_range].first
      text_end = hash[:display_text_range].last
      hash[:entities].each do |entity, values|
        hash[:entities][entity] = values.reject { |value|
          value[:indices].last < text_start || value[:indices].first > text_end
        }
        hash[:entities][entity].each_with_index do |value, index|
          hash[:entities][entity][index][:indices] = [
            value[:indices][0] - text_start,
            value[:indices][1] - text_start
          ]
        end
      end
    end
    hash
  end

  def strip_trailing_link?
    hash = main_tweet.to_h
    link_preview? && main_tweet.urls.first.indices.last == hash[:full_text].length
  end

  def method_missing(*args, &block)
    tweet.public_send(*args, *block)
  end
end
