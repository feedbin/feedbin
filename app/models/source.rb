class Source
  attr_accessor :response, :feeds

  def initialize(response)
    @response = response
    @feeds = []
  end

  def self.find(*args)
    source = new(*args)
    source.find
    source.feeds
  end

  def self.options(*args)
    source = new(*args)
    source.options
  end

  def document
    @document ||= begin
      parsed = response.parse(validate: false)
      parsed.document if parsed.respond_to?(:document)
    end
  end

  def document?
    !document.nil?
  end

  def create_from_url!(url)
    create_from_request!(Feedkit::Request.download(url))
  end

  def create_from_request!(response)
    feed = Feed.xml.where(feed_url: response.url).take
    if feed.present? && (feed.last_download.nil? || feed.last_download.before?(1.day.ago))
      response.persist!
      FeedCrawler::Parser.new.parse_and_save(feed, response.path, encoding: response.encoding.to_s, import: true)
    else
      feed = Feed.create_from_parsed_feed(response.parse)
    end
    feed
  rescue
    raise unless Rails.env.production?
  end

  def join_url(base, path)
    base = Addressable::URI.parse(base)
    path = Addressable::URI.parse(path)
    Addressable::URI.join(base, path).to_s
  end
end
