class FeedFinder

  def initialize(url)
    @url = url
    @cache = {}
  end

  def options
    @options ||= begin
      options = []
      options.concat(existing_feed) if options.empty?
      options.concat(page_links) if options.empty?
      options.concat(xml) if options.empty?
      options.concat(youtube) if options.empty?
      options
    end
  end

  def create_feed(option)
    feed = nil

    request = @cache[option.href]
    if !request
      request = FeedRequest.new(url: option.href)
    end

    feed = Feed.where(feed_url: option.href).take
    if !feed && request.body.present? && request.format == :xml
      parsed_feed = ParsedFeed.new(request.body, request)
      feed = Feed.create_from_parsed_feed(parsed_feed)
    end

    feed
  end

  private

  def existing_feed
    options = []
    feed = Feed.where(feed_url: @url).take
    if feed
      options.push(FeedOption.new(feed.feed_url, feed.feed_url, feed.title))
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

  def xml
    options = []
    if cache(@url).format == :xml
      url = cache(@url).last_effective_url
      options.push(FeedOption.new(url, url, url))
    end
    options
  end

  def youtube
    YoutubeOptions.new(cache(@url).last_effective_url).options
  end

  def cache(url)
    @cache[url] ||= FeedRequest.new(url: @url, clean: true)
    last_effective_url = @cache[@url].last_effective_url
    @cache[last_effective_url] = @cache[url]
    @cache[url]
  end

end
