class Embed::Twitter
  attr_reader :url

  def initialize(url)
    @url = url
  end

  def name
    data.dig("author_name")
  end

  def screen_name
    "@#{user}"
  end

  def permalink
    data.dig("url")
  end

  def date
    Time.parse document.search("blockquote > a").text
  end

  def content
    document.search("p").to_s
  end

  def profile_image_url
    "https://twitter.com/#{user}/profile_image?size=bigger"
  end

  def author_url
    data.dig("author_url")
  end

  def image_url
    @image_url ||= begin
      url = nil

      pics = document.search("a").each_with_object([]) { |anchor, array|
        if anchor.text&.start_with?("pic.twitter.com")
          array.push anchor.attr("href")
        end
      }

      unless pics.empty?
        page = URLCache.new(pics.last).body
        doc = Nokogiri::HTML5(page)
        image = doc.css("meta[property='og:image']")
        unless image.empty?
          url = image.first.attributes["content"].value
        end
      end

      url
    end
  end

  private

  OEMBED_URL = "https://publish.twitter.com/oembed"

  def user
    @user ||= data.dig("author_url")&.split("/")&.last
  end

  def document
    @document ||= Nokogiri::HTML5.fragment(data.dig("html"))
  end

  def data
    @data ||= begin
      options = {
        params: {
          url: url,
          omit_script: true,
        },
      }
      JSON.parse(URLCache.new(OEMBED_URL, options).body)
    end
  end
end
