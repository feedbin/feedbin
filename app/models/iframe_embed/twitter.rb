class IframeEmbed::Twitter
  attr_reader :url

  def self.download(*args)
    instance = new(*args)
    instance.name
    instance
  end

  def initialize(url)
    @url = url
  end

  def name
    data.safe_dig("author_name")
  end

  def screen_name
    "@#{user}"
  end

  def permalink
    data.safe_dig("url")
  end

  def date
    Time.parse document.search("blockquote > a").text
  end

  def content
    document.search("p").to_s
  end

  def profile_image_url
    TwitterUser.where_lower(screen_name: user).take&.profile_image || ActionController::Base.helpers.image_url("favicon-profile-default.png")
  end

  def author_url
    data.safe_dig("author_url")
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
        page = UrlCache.new(pics.last).body
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
    @user ||= data.safe_dig("author_url")&.split("/")&.last
  end

  def document
    @document ||= Nokogiri::HTML5.fragment(data.safe_dig("html"))
  end

  def data
    @data ||= begin
      options = {
        params: {
          url: url,
          omit_script: true
        }
      }
      JSON.parse(UrlCache.new(OEMBED_URL, options).body)
    end
  end
end
