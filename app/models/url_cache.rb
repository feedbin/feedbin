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
    # skip_nil keeps a failed response out of the cache. Without it one 503
    # turns into a permanent one: the error body gets stored under the url's
    # key with no expiry and every later caller is handed it as the page.
    @body, @headers = Rails.cache.fetch(cache_key, expires_in: 1.week, skip_nil: true) {
      # The url reaches here from entry content and from params, so the socket
      # resolves the host and refuses anything that is not routable on the
      # public internet, re-checking on every redirect hop.
      request = HTTP.timeout(write: 5, connect: 5, read: 10).follow(max_hops: 5)
        .get(url, **options, socket_class: Feedkit::PrivateAddressCheck::Socket)
      if request.status.success?
        [request.to_s, request.headers.to_h]
      end
    }
  end
end
