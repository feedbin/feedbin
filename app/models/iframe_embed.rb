class IframeEmbed
  SUPPORTED_URLS = []

  attr_reader :embed_url, :data

  def initialize(embed_url)
    @embed_url = URI(embed_url)
    @embed_url.scheme = "https"
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

  # subclass should implement these
  def channel_name; end
  def duration; end
  def profile_image; end

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
    "iframe_embed_#{Digest::SHA1.hexdigest(embed_url.to_s)}"
  end

  def fetch
    if oembed_url
      @data ||= begin
        Rails.cache.fetch("iframe_embed_counter_#{Digest::SHA1.hexdigest(oembed_params.to_s)}") {
          Librato.increment("iframe_embed.fetch", source: self.class.name.parameterize)
        }
        defaults = {
          url: embed_url.to_s
        }
        response = UrlCache.new(oembed_url, params: defaults.merge(oembed_params))
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
    url = normalize_url(url)
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
      IframeEmbed::Youtube,
      IframeEmbed::Vimeo,
      IframeEmbed::Ted,
      IframeEmbed::Spotify,
      IframeEmbed::Kickstarter,
      IframeEmbed::Soundcloud,
      IframeEmbed::Default
    ]
  end

  def self.normalize_url(url)
    if url.start_with?("https://cdn.embedly.com/widgets")
      parsed = Addressable::URI.parse(url)
      if parsed.query_values && parsed.query_values["src"]
        url = parsed.query_values["src"]
      end
    end
    url
  end

  def self.supported_urls
    []
  end
end
