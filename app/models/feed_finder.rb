class FeedFinder

  def initialize(url, config = {})
    @url = url
    @config = config
  end

  def create_feeds!
    feeds = nil

    if feeds.blank?
      feeds = Source::ExistingFeed.new(@url, @config).call
    end

    # Twitter

    # make request for page

    if feeds.blank?
      feeds = Source::MetaLinks.new(@url, @config).call
    end

    Rails.logger.info { "------------------------" }
    Rails.logger.info { feeds.inspect }
    Rails.logger.info { "------------------------" }

    # @options ||= begin
    #   options = []
    #   options.concat(existing_feed) if options.empty?
    #   options.concat(twitter) if options.empty?
    #   options.concat(page_links) if options.empty?
    #   options.concat(xml) if options.empty?
    #   options.concat(json_feed) if options.empty?
    #   options.concat(youtube) if options.empty?
    #   options.concat(guess) if options.empty?
    #   options.concat(rss_anchors) if options.empty?
    #   options
    # end

    feeds
  end

  private

  def existing_feed

  end

  def page_links
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

  def twitter
    TwitterFeed.new(@url, @config[:twitter_access_token], @config[:twitter_access_secret]).options
  end

end
