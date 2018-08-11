class IframeEmbed::Default < IframeEmbed

  def fetch

  end

  def title
    "Embed"
  end

  def subtitle
    embed_url.host.split(".").last(2).join(".")
  end

  def canonical_url
    embed_url.to_s
  end

  def image_url
    nil
  end

  def self.recognize_url?(url)
    true
  end

end