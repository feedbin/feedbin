class FeedFinder

  attr_reader :url

  def initialize(url)
    @url = url
    @request_cache = {}
  end

  def find_url
    feed_url = existing_feed_url(url)
    if feed_url
      feed_url = feed_url
    else
      @request_cache[@url] = FeedRequest.new(@url, true)
      if @request_cache[@url].format == :html
        feed_url = check_page(@request_cache[@url])
      else
        feed_url = request.last_effective_url
        @request_cache[request.last_effective_url] = @request_cache[@url]
      end
    end
    feed_url
  end

  def check_page(request)
    options = FeedOptions.new(request.body, request.last_effective_url).perform
    result = options
    if options.length == 0
      result = nil
    elsif options.length == 1
      result = options.first[:href]
      existing = existing_feed_url(result)
      if existing
        result = existing
      end
    end
    result
  end

  def existing_feed_url(url)
    feed_url = nil
    feed = Feed.where(feed_url: url).take
    if feed
      feed_url = feed.feed_url
    end
    feed_url
  end

  def force
    feed = nil
    feed_url = find_url
    if feed_url.kind_of?(Array)
      feed_url = feed_url.first[:href]
    end
    if feed_url
      feed = Feed.where(feed_url: url).take
      if !feed
        feed = create_feed(feed_url)
      end
    end
    feed
  end

  def create_feed(feed_url)
    feed = nil
    @request_cache[feed_url] = FeedRequest.new(feed_url) if !@request_cache[feed_url]
    request = @request_cache[feed_url]
    if request.format == :xml
      parsed_feed = ParsedFeed.new(request.body, request)
      feed = Feed.create_from_parsed_feed(parsed_feed)
    end
    feed
  end

end