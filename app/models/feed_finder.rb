class FeedFinder
  def initialize(url, config = {})
    @url = url
    @config = config.merge({
      request: Feedkit::Request.new(url: @url, clean: true),
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
      feeds = Source::XML.new(@url, @config).call
    end

    if feeds.blank?
      feeds = Source::JSONFeed.new(@url, @config).call
    end

    if feeds.blank?
      feeds = Source::Youtube.new(@url, @config).call
    end

    if feeds.blank?
      feeds = Source::Reddit.new(@url, @config).call
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
