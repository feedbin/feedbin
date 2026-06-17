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
      request = HTTP.timeout(write: 5, connect: 5, read: 10).follow(max_hops: 5).get(url, options)
      [request.to_s, request.headers.to_h]
    }
  end
end
