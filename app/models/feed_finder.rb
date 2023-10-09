class FeedFinder

  attr_reader :url, :response, :import_mode

  def initialize(url, import_mode: false, username: nil, password: nil)
    @url          = url
    @import_mode  = import_mode
    @username     = username
    @password     = password
  end

  def self.feeds(url, **args)
    options = new(url, **args).find
    options.uniq { |option| option.id }
  end

  def find
    feeds = []

    existing_feed = Feed.xml.where(feed_url: url).take

    if feeds.empty?
      feeds = Source::ExistingFeed.find(response)
    end

    if feeds.empty?
      feeds = Source::Xml.find(response)
    end

    if feeds.empty? && !import_mode?
      feeds = Source::MetaLinks.find(response)
    end

    if feeds.empty?
      feeds = Source::KnownPattern.find(response)
    end

    if feeds.empty? && !import_mode?
      feeds = Source::BodyLinks.find(response)
    end

    if feeds.empty? && !import_mode?
      feeds = Source::Guess.find(response)
    end

    if feeds.empty? && import_mode? && existing_feed.present?
      feeds.push(existing_feed)
    end

    feeds
  rescue Feedkit::Unauthorized
    raise
  rescue => exception
    if import_mode? && existing_feed.present?
      return [existing_feed]
    elsif import_mode? || Rails.env.development?
      raise exception
    else
      Rails.logger.error exception.message
      Rails.logger.error exception.backtrace.join("\n")
      ErrorService.notify(exception)
      feeds
    end
  end

  def find_options
    feeds = []

    if feeds.empty?
      feeds = Source::MetaLinks.options(response)
    end

    if feeds.empty?
      feeds = Source::BodyLinks.options(response)
    end

    feeds
  end

  def import_mode?
    import_mode
  end

  def response
    @response ||= Feedkit::Request.download(clean_url(url), username: @username, password: @password)
  end

  def clean_url(url)
    uri = Addressable::URI.heuristic_parse(url)
    uri.scheme = "http" unless ["http", "https"].include?(uri.scheme)
    Addressable::URI.heuristic_parse(uri.to_s).to_s
  end
end
