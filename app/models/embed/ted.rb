class Embed::Ted < IframeEmbed
  def self.supported_urls
    [
      %r{.*?//embed\.ted\.com/talks/(.*?)(#|\?|$)},
    ]
  end

  def oembed_url
    @oembed_url ||= "https://www.ted.com/services/v1/oembed.json"
  end

  def image_url
    url = URI(super)
    url.query = nil
    url.to_s
  end
end
