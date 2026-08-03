class UrlCache
  attr_reader :url, :options

  def initialize(url, options = {})
    @url = url
    @options = options
  end

  def cache_key
    "url_cache_#{Digest::SHA1.hexdigest("#{url}#{options}")}"
  end

  def body
    result && @body
  end

  def headers
    result && @headers
  end

  private

  def result
    @body, @headers = Rails.cache.fetch(cache_key) {
      # The url reaches here from entry content and from params, so the socket
      # resolves the host and refuses anything that is not routable on the
      # public internet, re-checking on every redirect hop.
      request = HTTP.timeout(write: 5, connect: 5, read: 10).follow(max_hops: 5)
        .get(url, **options, socket_class: Feedkit::PrivateAddressCheck::Socket)
      [request.to_s, request.headers.to_h]
    }
  end
end
