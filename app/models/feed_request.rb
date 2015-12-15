class FeedRequest

  attr_reader :url

  def initialize(url:, clean: false, options: {})
    @url = url
    @options = options
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
      result = result.lstrip
      if result == ""
        result = nil
      end
      result
    rescue
      nil
    end
  end

  def format
    if body && /^\s*<(?:!DOCTYPE\s+)?html[\s>]/i === body[0, 512]
      :html
    else
      :xml
    end
  end

  def last_effective_url
    @last_effective_url ||= response.last_effective_url
  end

  def last_modified
    @last_modified ||= begin
      Time.parse(headers[:last_modified])
    rescue
      nil
    end
  end

  def etag
    @etag ||= begin
      content = headers[:etag]
      if content && content.match(/^"/) && content.match(/"$/)
        content = content.gsub(/^"/, "").gsub(/"$/, "")
      end
      content
    end
  end

  def status
    @status ||= response.response_code
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
      if @options.has_key?(:if_modified_since)
        curl.headers["If-Modified-Since"] = @options[:if_modified_since].httpdate
      end
      if @options.has_key?(:if_none_match)
        curl.headers["If-None-Match"] = @options[:if_none_match]
      end
      curl.headers["User-Agent"] = @options[:user_agent] || "Feedbin"
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
    url = url.gsub(/^ht*p(s?):?\/*/, 'http\1://')
    url = url.gsub(/^feed:\/\//, 'http://')
    if url !~ /^https?:\/\//
      url = "http://#{url}"
    end
    url
  end

end