class DiffbotParser
  BASE_URL = "https://api.diffbot.com/v3/article"

  attr_reader :url, :body

  def initialize(url, body = nil)
    @url = url
    @body = body
  end

  def self.parse(url)
    new(url)
  end

  def title
    result["title"]
  end

  def content
    result["html"]
  end

  def author
    result["author"]
  end

  def published
    if result["estimatedDate"]
      Time.parse(result["estimatedDate"])
    end
  end

  def date_published
    result["estimatedDate"]
  end

  def domain
    @domain ||= begin
      parsed_url = result["resolvedPageUrl"] || result["pageUrl"]
      URI.parse(parsed_url).host
    end
  end

  private

  def result
    @result ||= begin
      response = request(norender: "norender")
      if response["text"] && !response["html"]
        response = request
      end
      response
    end
  end

  def request(options = {})
    query = {
      url: url,
      discussion: false,
      token: ENV["DIFFBOT_TOKEN"],
    }.merge(options)
    uri = URI.parse(BASE_URL)
    uri.query = query.to_query
    response = HTTP.timeout(:global, write: 10, connect: 10, read: 10)
    response = if body
      response.headers(content_type: "text/html; charset=utf-8").post(uri, body: body)
    else
      response.get(uri)
    end
    response.parse["objects"].first
  end

  def marshal_dump
    {
      result: result,
      url: url,
      body: body,
    }
  end

  def marshal_load(data)
    @result = data[:result]
    @url = data[:url]
    @body = data[:body]
  end
end
