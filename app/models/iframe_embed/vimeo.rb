class IframeEmbed::Vimeo < IframeEmbed

  def self.supported_urls
    [
      %r(https?://player\.vimeo\.com/video/(.*?)(#|\?|$))
    ]
  end

  def oembed_url
    @oembed_url ||= "https://vimeo.com/api/oembed.json"
  end

  def image_url
    super.gsub /_\d+.jpg/, ".jpg"
  end

  def iframe_params
    { "autoplay" => "1" }
  end

  def canonical_url
    "https://vimeo.com/#{embed_url_data[1]}"
  end

end