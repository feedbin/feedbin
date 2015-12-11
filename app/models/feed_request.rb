class FeedRequest

  attr_reader :url

  def initialize(url, clean = false)
    @url = url
    if clean
      @url = clean_url
    end
  end

  def body
    @body ||= begin
      result = response.body_str
      if gzipped?
        result = gunzip(result)
      end
      result.lstrip
    rescue
      nil
    end
  end

  def format
    if /^\s*<(?:!DOCTYPE\s+)?html[\s>]/i === body[0, 512]
      :html
    else
      :xml
    end
  end

  def last_effective_url
    @last_effective_url ||= response.last_effective_url
  end

  def last_modified
    Time.parse(headers[:last_modified])
  rescue
    nil
  end

  def etag
    headers[:etag] ? headers[:etag].gsub(/^"/, "").gsub(/"$/, "") : nil
  end

  def headers
    @headers ||= begin
      http_headers = response.header_str.split(/[\r\n]+/).map(&:strip)
      http_headers = http_headers.flat_map do |string|
        string.scan(/^(\S+):\s*(.+)/)
      end
      http_headers.each_with_object({}) do |(header, value), hash|
        header = header.downcase.gsub("-", "_").to_sym
        hash[header] = value
      end
    end
  end

  private

  def gunzip(string)
    string = StringIO.new(string)
    gz =  Zlib::GzipReader.new(string)
    result = gz.read
    gz.close
    result
  rescue Zlib::GzipFile::Error
    string
  end

  def gzipped?
    headers[:content_encoding] =~ /gzip/i
  end

  def response
    @response ||= Curl::Easy.perform(@url) do |curl|
      curl.headers["User-Agent"] = "Feedbin"
      curl.headers["Accept-Encoding"] = "gzip"
      curl.connect_timeout = 10
      curl.follow_location = true
      curl.max_redirects = 5
      curl.ssl_verify_peer = false
      curl.timeout = 20
    end
  end

  def clean_url
    url = @url
    url = url.strip
    url = url.gsub(/^ht*p(s?):?\/*/, "http\1://")
    url = url.gsub(/^feed:/, "http:")
    Addressable::URI.heuristic_parse(url).to_s
  end

end