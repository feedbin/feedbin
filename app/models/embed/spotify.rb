class Embed::Spotify < IframeEmbed
  def self.supported_urls
    [
      %r{.*?//open\.spotify\.com/embed/(track|artist)/(.*?)(#|\?|$)},
      %r{.*?//open\.spotify\.com/embed/user/(.*?)/playlist/(.*?)(#|\?|$)},
    ]
  end

  def oembed_url
    @oembed_url ||= "https://embed.spotify.com/oembed"
  end

  def oembed_params
    {url: url_param, format: "json"}
  end

  private

  def url_param
    url = embed_url.dup
    url.path = url.path.sub("/embed", "")
    url.to_s
  end
end
