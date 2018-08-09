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
    author_data.dig("user", "profile_pic_url")
  end

  def content
    data.dig("title")
  end

  private

    OEMBED_URL = "https://api.instagram.com/oembed"
    PROFILE_URL = "https://i.instagram.com/api/v1/users/%d/info/"

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
            omitscript: true
          }
        }
        JSON.parse(URLCache.new(OEMBED_URL, options).body)
      end
    end

    def author_data
      @author_data ||= begin
        options = {
          params: {
            url: url,
            omitscript: true
          }
        }
        JSON.parse(URLCache.new((PROFILE_URL % author_id), options).body)
      end
    end

end