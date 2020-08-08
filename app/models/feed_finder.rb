class FeedFinder

  attr_reader :url, :basic_auth, :twitter_auth, :response, :import_mode

  def initialize(url, import_mode: false, basic_auth: nil, twitter_auth: nil)
    @url = url
    @import_mode = import_mode
    @basic_auth = basic_auth
    @twitter_auth = twitter_auth
  end

  def self.feeds(url, **args)
    new(url, **args).find
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

    if feeds.empty? && !import_mode?
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
    @response ||= Feedkit::Request.download(clean_url(url))
  end

  def clean_url(url)
    uri = Addressable::URI.heuristic_parse(url)
    uri.scheme = "http" unless ["http", "https"].include?(uri.scheme)
    Addressable::URI.heuristic_parse(uri.to_s).to_s
  end
end
