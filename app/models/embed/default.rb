class Embed::Default < IframeEmbed
  def fetch
    @page ||= begin
      URLCache.new(canonical_url)
    end
  end

  def title
    doc = Nokogiri::HTML5(@page.body)
    title = doc.css("title")
    if title.present?
      title.first.text
    else
      "Embed"
    end
  end

  def type
    clean_name
  end

  def subtitle
    "Embed from #{embed_url.host.split(".").last(2).join(".")}"
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
