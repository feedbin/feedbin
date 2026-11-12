class MercuryParser
  SETTINGS = %w[EXTRACT_HOST EXTRACT_USER EXTRACT_SECRET].freeze

  class NotConfigured < StandardError
    def initialize(message = "The extract service is not configured. Set #{SETTINGS.join(", ")}.")
      super
    end
  end

  attr_reader :url

  # The extract service is optional. Development runs without it.
  def self.configured?
    SETTINGS.all? { ENV[_1].present? }
  end

  def initialize(url, data: nil, html: nil)
    @url = url
    @html = html
    load_data(data) if data
  end

  def self.parse(...)
    Librato.increment "readability.first_parse"
    instance = new(...)
    instance.result
    instance
  end

  def title
    result["title"]
  end

  # for compatibility with Entry
  def plain_title_with_default
    result["title"]
  end

  def content
    result["content"]
  end

  def author
    result["author"]
  end

  def published
    if result["date_published"]
      Time.parse(result["date_published"])
    end
  rescue
    nil
  end

  def date_published
    result["date_published"]
  end

  def domain
    result["domain"]
  end

  def fully_qualified_url
    @url
  end
  alias_method :base_url, :fully_qualified_url

  def to_h
    {
      result: result,
      url: url
    }
  end

  # nil when the extract service is not configured, so a caller that only
  # hands the URL on (Entry#extracted_content_url, once for every entry of an
  # API page) has nothing to rescue.
  def service_url
    return nil unless self.class.configured?

    @service_url ||= begin
      digest = OpenSSL::Digest.new("sha1")
      signature = OpenSSL::HMAC.hexdigest(digest, ENV["EXTRACT_SECRET"], url)
      base64_url = Base64.urlsafe_encode64(url).delete("\n")
      URI.parse(ENV["EXTRACT_HOST"]).tap do
        it.path  = "/parser/#{ENV["EXTRACT_USER"]}/#{signature}"
        it.query = "base64_url=#{base64_url}"
      end.to_s
    end
  end

  def result
    @result ||= begin
      raise NotConfigured unless self.class.configured?

      response = HTTP.timeout(write: 5, connect: 5, read: 5)
        .use(:auto_inflate)
        .headers("Accept-Encoding" => "gzip")

      response = if @html
        response.post(service_url, json: {body: @html})
      else
        response.get(service_url)
      end

      response.parse
    end
  end

  private

  def marshal_dump
    to_h
  end

  def marshal_load(data)
    @result = data[:result]
    @url = data[:url]
  end

  def load_data(data)
    @result = data["result"]
    @url = data["url"]
  end
end
