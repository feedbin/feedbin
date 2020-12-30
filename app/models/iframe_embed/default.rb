class IframeEmbed::Default < IframeEmbed
  def fetch
    @page ||= begin
      UrlCache.new(canonical_url)
    end
  end

  def title
    doc = Nokogiri::HTML5(@page.body) rescue nil
    title = doc&.css("title")
    title&.first&.text || "Embed"
  end

  def type
    clean_name
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
