class FeedFinder
  def initialize(url, config = {})
    @url = url
    @config = config.merge({
      request: Feedkit::Request.new(url: @url, clean: true)
    })
  end

  def create_feeds!
    feeds = nil

    if feeds.blank?
      feeds = Source::ExistingFeed.new(@url, @config).call
    end

    if feeds.blank?
      feeds = Source::TwitterData.new(@url, @config).call
    end

    if feeds.blank?
      feeds = Source::MetaLinks.new(@url, @config).call
    end

    if feeds.blank?
      feeds = Source::Xml.new(@url, @config).call
    end

    if feeds.blank?
      feeds = Source::JsonFeed.new(@url, @config).call
    end

    if feeds.blank?
      feeds = Source::KnownPattern.new(@url, @config).call
    end

    if feeds.blank?
      feeds = Source::BodyLinks.new(@url, @config).call
    end

    if feeds.blank?
      feeds = Source::Guess.new(@url, @config).call
    end

    feeds
  end
end
