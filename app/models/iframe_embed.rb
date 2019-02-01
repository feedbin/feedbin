class IframeEmbed
  SUPPORTED_URLS = []

  attr_reader :embed_url, :data

  def initialize(embed_url)
    @embed_url = URI(embed_url)
    @embed_url.scheme ||= "http"
    Librato.increment("iframe_embed.source", source: @embed_url.host)
  end

  def title
    data && data["title"]
  end

  def subtitle
    data && data["provider_name"]
  end

  def canonical_url
    data && data["url"] || embed_url.to_s
  end

  def image_url
    data && data["thumbnail_url"]
  end

  def type
    data && data["type"]
  end

  def iframe_src
    url = embed_url.dup
    params = Rack::Utils.parse_nested_query(url.query)
    params = params.merge(iframe_params)
    url.query = params.to_query
    url.to_s
  end

  def iframe_params
    {}
  end

  def cache_key
    Digest::SHA1.hexdigest(embed_url.to_s)
  end

  def fetch
    if oembed_url
      @data ||= begin
        defaults = {
          url: embed_url.to_s,
        }
        response = URLCache.new(oembed_url, params: defaults.merge(oembed_params))
        JSON.parse(response.body)
      end
    end
  end

  def clean_name
    self.class.name.demodulize.downcase
  end

  def embed_url_data
    @embed_url_data ||= self.class.recognize_url?(embed_url.to_s)
  end

  def oembed_url
    nil
  end

  def oembed_params
    {}
  end

  def self.recognize_url?(src_url)
    if supported_urls.find { |url| src_url =~ url }
      Regexp.last_match
    else
      false
    end
  end

  def self.fetch(url)
    parser = find_embed_source(url)
    parser = parser.new(url)
    parser.fetch
    parser
  end

  def self.find_embed_source(url)
    embed_sources.detect { |klass| klass.recognize_url?(url) }
  end

  def self.embed_sources
    [
      Embed::Youtube,
      Embed::Vimeo,
      Embed::Ted,
      Embed::Spotify,
      Embed::Kickstarter,
      Embed::Soundcloud,
      Embed::Default,
    ]
  end

  def self.supported_urls
    []
  end
end
