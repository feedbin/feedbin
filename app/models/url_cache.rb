class URLCache
  attr_reader :url, :options

  def initialize(url, options = {})
    @url = url
    @options = options
  end

  def cache_key
    "#{url}#{options.to_s}"
  end

  def body
    result && @body
  end

  def headers
    result && @headers
  end

  private

  def result
    @body, @headers = Rails.cache.fetch(cache_key) do
      request = HTTP.follow(max_hops: 5).get(url, options)
      [request.to_s, request.headers.to_h]
    end
  end
end
