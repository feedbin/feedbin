class ParsedTwitterFeed

  attr_reader :feed, :entries

  FEED_ATTRIBUTES = %i(etag feed_url last_modified self_url site_url title feed_type options).freeze

  def initialize(url, tweets, type, value, options = {})
    @url = url
    @tweets = tweets
    @type = type
    @value = value
    @options = options
  end

  def etag
    nil
  end

  def feed_url
    @url
  end

  def last_modified
    nil
  end

  def self_url
    @url
  end

  def site_url
    @url
  end

  def feed_type
    :twitter
  end

  def options
    @options
  end

  def title
    case @type
    when :user
      "@#{@value}"
    when :search
      "Twitter Search: #{@value}"
    when :list
      "Twitter List: @#{@value}"
    when :home
      "Twitter"
    end
  end

  def entries
    @entries ||= begin
      @tweets.map do |tweet|
        ParsedTweetEntry.new(tweet, @url)
      end
    end
  end

  def to_feed
    @to_feed ||= begin
      FEED_ATTRIBUTES.each_with_object({}) do |attribute, hash|
        hash[attribute] = self.respond_to?(attribute) ? self.send(attribute) : nil
      end
    end
  end

end
