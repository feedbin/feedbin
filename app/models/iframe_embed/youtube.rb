class IframeEmbed::Youtube < IframeEmbed

  def self.supported_urls
    [
      %r(https?://www\.youtube\.com/embed/(.*?)(\?|$)),
      %r(https?://www\.youtube-nocookie\.com/embed/(.*?)(\?|$)),
    ]
  end

  def oembed_url
    @oembed_url ||= "https://www.youtube.com/oembed"
  end

  def image_url
    data["thumbnail_url"].sub "hqdefault", "maxresdefault"
  end

  def canonical_url
    "https://youtu.be/#{embed_url_data[1]}"
  end

  def oembed_params
    {url: canonical_url, format: "json"}
  end

end