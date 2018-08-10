class IframeEmbed::Default < IframeEmbed

  def fetch

  end

  def title
    "Embed"
  end

  def subtitle
    embed_url.host
  end

  def canonical_url
    embed_url.to_s
  end

  def self.recognize_url?(url)
    true
  end

end