class IframeEmbed::Youtube < IframeEmbed

  SUPPORTED_URLS = [
    %r(https?://www\.youtube\.com/embed/(.*?)(\?|$)),
    %r(https?://www\.youtube-nocookie\.com/embed/(.*?)(\?|$)),
  ]

  OEMBED_URL = "https://www.youtube.com/oembed"

  def title
    data["title"]
  end

  def subtitle
    data["provider_name"]
  end

  def image_url
    data["thumbnail_url"].sub "hqdefault", "maxresdefault"
  end

  def image_url_fallback
    data["thumbnail_url"]
  end

  def fetch
    @data ||= begin
      options = {
        params: {
          format: "json",
          url: video_url
        }
      }
      JSON.parse(URLCache.new(OEMBED_URL, options).body)
    end
  end

  def video_id
    if SUPPORTED_URLS.find { |url| embed_url =~ url } && $1
      $1
    else
      false
    end
  end

  def self.recognize_url?(url)
    instance = self.new(url)
    !!(instance.video_id)
  end

  private

    def video_url
      "https://youtu.be/#{video_id}"
    end

end