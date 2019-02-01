class Embed::Youtube < IframeEmbed
  def self.supported_urls
    [
      %r{.*?//www\.youtube\.com/embed/(.*?)(\?|$)},
      %r{.*?//www\.youtube-nocookie\.com/embed/(.*?)(\?|$)},
      %r{.*?//youtube\.com/embed/(.*?)(\?|$)},
      %r{.*?//youtube-nocookie\.com/embed/(.*?)(\?|$)},
    ]
  end

  def oembed_url
    @oembed_url ||= "https://www.youtube.com/oembed"
  end

  def image_url
    url = data["thumbnail_url"].sub "hqdefault", "maxresdefault"
    status = Rails.cache.fetch("youtube_thumb_status:#{url}") {
      HTTP.head(url).status
    }
    if status == 200
      url
    else
      data["thumbnail_url"]
    end
  end

  def canonical_url
    "https://youtu.be/#{embed_url_data[1]}"
  end

  def iframe_params
    {
      "autoplay" => "1",
      "rel" => "0",
      "showinfo" => "0",
    }
  end

  def oembed_params
    {url: canonical_url, format: "json"}
  end
end
