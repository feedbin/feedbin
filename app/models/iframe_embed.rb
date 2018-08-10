class IframeEmbed

  attr_reader :embed_url, :data

  def initialize(embed_url)
    @embed_url = embed_url
  end

  def clean_name
    self.class.name.demodulize.downcase
  end

  def image_url
    false
  end

  def image_url_fallback
    false
  end

  def self.fetch(url)
    parser = find_embed_source(url)
    parser = parser.new(url)
    parser.fetch()
    parser
  end

  def self.find_embed_source(url)
    embed_sources.detect { |klass| klass.recognize_url?(url) }
  end

  def self.embed_sources
    [
      IframeEmbed::Youtube,
      IframeEmbed::Default
    ]
  end

end