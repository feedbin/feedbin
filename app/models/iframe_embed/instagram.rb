class IframeEmbed::Instagram
  attr_reader :url

  def initialize(url)
    @url = url
  end

  def screen_name
    data.dig("author_name")
  end

  def permalink
    "https://www.instagram.com/p/#{shortcode}/"
  end

  def author_url
    "https://instagram.com/#{screen_name}"
  end

  def media_url
    data.dig("thumbnail_url")
  end

  def profile_image_url
    nil
  end

  private

  OEMBED_URL = "https://graph.facebook.com/v9.0/instagram_oembed"

  def shortcode
    @shortcode ||= URI.parse(@url).path.split("/").last
  end

  def data
    @data ||= begin
      options = {
        params: {
          access_token: ENV["FACEBOOK_ACCESS_TOKEN"],
          url: url,
          fields: "thumbnail_url,author_name"
        }
      }
      response = UrlCache.new(OEMBED_URL, options).body
      JSON.parse(response)
    end
  end

  def page_data
    @page_data ||= begin
      UrlCache.new(permalink).body
    end
  end
end
