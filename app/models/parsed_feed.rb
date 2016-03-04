class ParsedFeed

  attr_reader :feed, :entries

  FEED_ATTRIBUTES = %i(etag feed_url last_modified self_url site_url title).freeze

  def initialize(xml, feed_request, base_url = nil)
    @xml = xml
    @feed_request = feed_request
    @base_url = base_url
  end

  def feed
    @feed ||= Feedjira::Feed.parse(@xml)
  end

  def title
    @title ||= feed.title ? feed.title.strip : "(No title)"
  end

  def feed_url
    @feed_url ||= @feed_request.last_effective_url
  end

  def site_url
    @site_url ||= begin
      if feed.url
        url = feed.url
      else
        if feed_url =~ /feedburner\.com/
          url = last_effective_url(feed.entries.first.url)
          url = url_from_host(url)
        else
          url = url_from_host(feed_url)
        end
      end
      url
    end
  end

  def self_url
    @self_url ||= begin
      url = feed_url
      if feed.self_url
        url = feed.self_url.strip
        if !url.match(/^http/)
          url = URI.join(feed_url, url).to_s
        end
      end
      url
    rescue
      feed_url
    end
  end

  def last_modified
    @feed_request.last_modified
  end

  def etag
    @feed_request.etag
  end

  def hubs
    @hubs = feed.respond_to?(:hubs) ? feed.hubs : []
  end

  def entries
    @entries ||= begin
      entries = []
      if feed.entries.respond_to?(:any?) && feed.entries.any?
        entries = feed.entries.map do |entry|
          ParsedEntry.new(entry, base_url)
        end
        entries = entries.uniq { |entry| entry.public_id }
      end
      entries
    end
  end

  def to_feed
    @to_feed ||= begin
      FEED_ATTRIBUTES.each_with_object({}) do |attribute, hash|
        hash[attribute] = self.send(attribute)
      end
    end
  end

  private

  def base_url
    @base_url || feed_url
  end

  def url_from_host(link)
    uri = URI.parse(link)
    URI::HTTP.build(host: uri.host).to_s
  end

  def last_effective_url(url)
    result = Curl::Easy.http_head(url) do |curl|
      curl.headers["User-Agent"] = "Feedbin"
      curl.connect_timeout = 5
      curl.follow_location = true
      curl.max_redirects = 5
      curl.ssl_verify_peer = false
      curl.timeout = 5
    end
    result.last_effective_url
  end

end
