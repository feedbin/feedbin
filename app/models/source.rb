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

  def create_from_request!(result)
    feed = Feed.xml.where(feed_url: result.url).take
    if feed.nil?
      feed = Feed.create_from_parsed_feed(result.parse)
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
