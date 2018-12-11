class Embed::Instagram
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
    data.dig("author_url")
  end

  def media_url
    "https://instagram.com/p/#{shortcode}/media/?size=l"
  end

  def profile_image_url
    page_data.scan(/"profile_pic_url":"([^"]+)","username":"#{Regexp.quote(screen_name)}"/).flatten.first
  rescue
    nil
  end

  def content
    data.dig("title")
  end

  private

  OEMBED_URL = "https://api.instagram.com/oembed"

  def shortcode
    @shortcode ||= URI.parse(@url).path.split("/").last
  end

  def author_id
    data.dig("author_id")
  end

  def data
    @data ||= begin
      options = {
        params: {
          url: url,
          omitscript: true,
        },
      }
      response = URLCache.new(OEMBED_URL, options).body
      JSON.parse(response)
    end
  end

  def page_data
    @page_data ||= begin
      URLCache.new(permalink).body
    end
  end
end
