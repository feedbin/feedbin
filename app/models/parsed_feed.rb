class ParsedFeed

  attr_reader :feed, :entries

  FEED_ATTRIBUTES = %i(etag feed_url last_modified self_url site_url title).freeze

  def initialize(body, feed_request, base_url = nil)
    @body = body
    @feed_request = feed_request
    @base_url = base_url
  end

  def feed_url
    @feed_url ||= @feed_request.last_effective_url
  end

  def last_modified
    @feed_request.last_modified
  end

  def etag
    @feed_request.etag
  end

  def to_feed
    @to_feed ||= begin
      FEED_ATTRIBUTES.each_with_object({}) do |attribute, hash|
        hash[attribute] = self.respond_to?(attribute) ? self.send(attribute) : nil
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
