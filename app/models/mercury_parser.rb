class MercuryParser
  host = ENV["MERCURY_HOST"] || "mercury.postlight.com"

  BASE_URL = "https://#{host}/parser"

  attr_reader :url

  def initialize(url, data = nil)
    @url = url
    load_data(data) if data
  end

  def self.parse(url)
    new(url)
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

  def to_h
    {
      result: result,
      url: url,
    }
  end

  private

  def result
    @result ||= begin
      query = {url: url}
      uri = URI.parse(BASE_URL)
      uri.query = query.to_query
      response = HTTP.timeout(:global, write: 3, connect: 3, read: 3).headers("x-api-key" => ENV["MERCURY_API_KEY"]).get(uri)
      response.parse
    end
  end

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
