class Embed::Soundcloud < IframeEmbed
  def self.supported_urls
    [
      %r{.*?//w\.soundcloud\.com/player},
    ]
  end

  def oembed_url
    @oembed_url ||= "https://soundcloud.com/oembed"
  end

  def oembed_params
    params = Rack::Utils.parse_nested_query(embed_url.query)
    {url: params["url"], format: "json"}
  end
end
