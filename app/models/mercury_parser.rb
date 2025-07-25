class MercuryParser
  attr_reader :url

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

  def self.parse_with_html(...)
    Librato.increment "readability.first_parse"
    instance = new(...)
    instance.result
    instance
  end

  def title
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

  def service_url
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
