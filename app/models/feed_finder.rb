class FeedFinder

  def initialize(url)
    @url = url
    @cache = {}
  end

  def options
    @options ||= begin
      options = []
      if option = existing_option(@url)
        options.push(option)
      else
        @cache[@url] = FeedRequest.new(@url, true)
        if @cache[@url].format == :html
          options = FeedOptions.new(@cache[@url].body, @cache[@url].last_effective_url).perform
        else
          url = @cache[@url].last_effective_url
          options.push(FeedOption.new(url, url, url))
          @cache[url] = @cache[@url]
        end
      end
      options
    end
  end

  def create_feed(option)
    feed = nil

    request = @cache[option.href]
    if !request
      request = FeedRequest.new(option.href)
    end

    feed = Feed.where(feed_url: option.href).take
    if !feed && request.format == :xml
      parsed_feed = ParsedFeed.new(request.body, request)
      feed = Feed.create_from_parsed_feed(parsed_feed)
    end

    feed
  end

  private

  def existing_option(url)
    option = nil
    feed = Feed.where(feed_url: url).take
    if feed
      option = FeedOption.new(feed.feed_url, feed.feed_url, feed.title)
    end
    option
  end

end
