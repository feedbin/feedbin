class FeedFinder

  attr_reader :url, :twitter_auth, :response, :import_mode

  def initialize(url, import_mode: false, twitter_auth: nil, username: nil, password: nil)
    @url          = url
    @import_mode  = import_mode
    @twitter_auth = twitter_auth
    @username     = username
    @password     = password
  end

  def self.feeds(url, **args)
    options = new(url, **args).find
    options.uniq { |option| option.id }
  end

  def find
    feeds = []

    if feeds.empty?
      feeds = Source::TwitterData.find(url, twitter_auth)
    end

    if feeds.empty?
      feeds = Source::ExistingFeed.find(response)
    end

    if feeds.empty?
      feeds = Source::Xml.find(response)
    end

    if feeds.empty?
      feeds = Source::KnownPattern.find(response)
    end

    if feeds.empty? && !import_mode?
      feeds = Source::MetaLinks.find(response)
    end

    if feeds.empty? && !import_mode?
      feeds = Source::BodyLinks.find(response)
    end

    if feeds.empty? && !import_mode?
      feeds = Source::Guess.find(response)
    end

    feeds
  rescue Feedkit::Unauthorized
    raise
  rescue => exception
    if Rails.env.production?
      Rails.logger.error exception.message
      Rails.logger.error exception.backtrace.join("\n")
      Honeybadger.notify(exception)
      feeds
    else
      raise exception
    end
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
