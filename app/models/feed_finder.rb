class FeedFinder

  def initialize(url, config = {})
    @url = url
    @cache = {}
    @config = config
  end

  def options
    @options ||= begin
      options = []
      options.concat(existing_feed) if options.empty?
      options.concat(twitter) if options.empty?
      options.concat(page_links) if options.empty?
      options.concat(xml) if options.empty?
      options.concat(json_feed) if options.empty?
      options.concat(youtube) if options.empty?
      options.concat(guess) if options.empty?
      options.concat(rss_anchors) if options.empty?
      options
    end
  end

  def create_feeds!
    options.each_with_object([]) do |option, array|
      array.push(create_feed(option))
    end.compact.uniq
  end

  def create_feed(option)
    Librato.increment("feed_finder.#{option.source}")
    feed = Feed.where(feed_url: option.href).take

    if !feed
      request = @cache[option.href]
      if !request
        request = FeedRequest.new(url: option.href)
      end

      feed = Feed.where(feed_url: request.last_effective_url).take
      if !feed && request.body.present? && [:xml, :json_feed].include?(request.format)
        if request.format == :xml
          parsed_feed = ParsedXMLFeed.new(request.body, request)
        elsif request.format == :json_feed
          parsed_feed = ParsedJSONFeed.new(request.body, request)
        end
        feed = Feed.create_from_parsed_feed(parsed_feed)
      end
    end
    feed
  end

  private

  def existing_feed
    options = []
    feed = Feed.where(feed_url: @url).take
    if feed
      options.push(FeedOption.new(feed.feed_url, feed.feed_url, feed.title, "existing_feed"))
    end
    options
  end

  def page_links
    options = []
    if cache(@url).format == :html
      options = FeedOptions.new(cache(@url).body, cache(@url).last_effective_url).perform
    end
    options
  end

  def rss_anchors
    options = []
    if cache(@url).format == :html
      options = RssAnchors.new(cache(@url).body, cache(@url).last_effective_url, limit: 5).perform
    end
    options
  end

  def xml
    options = []
    if cache(@url).format == :xml
      url = cache(@url).last_effective_url
      options.push(FeedOption.new(url, url, url, "xml"))
    end
    options
  end

  def json_feed
    options = []
    if cache(@url).format == :json_feed
      url = cache(@url).last_effective_url
      options.push(FeedOption.new(url, url, url, "json_feed"))
    end
    options
  end

  def youtube
    YoutubeOptions.new(cache(@url).last_effective_url).options
  end

  def guess
    options = []
    if cache(@url).format == :html
      host = URI.parse(cache(@url).last_effective_url).host
      if cache(@url).body =~ /tumblr\.com/i
        url = URI::HTTP.build(host: host, path: "/rss").to_s
        options.push(FeedOption.new(url, url, url, "guess"))
      elsif cache(@url).body =~ /wordpress/i
        url = URI::HTTP.build(host: host, path: "/feed").to_s
        options.push(FeedOption.new(url, url, url, "guess"))
      end
    end
    options
  end

  def cache(url)
    @cache[url] ||= FeedRequest.new(url: @url, clean: true)
    last_effective_url = @cache[@url].last_effective_url
    @cache[last_effective_url] = @cache[url]
    @cache[url]
  end

  def twitter
    TwitterFeed.new(@url, @config[:twitter_access_token], @config[:twitter_access_secret]).options
  end

end
