class Embed::Kickstarter < IframeEmbed
  def self.supported_urls
    [
      %r{.*?//www\.kickstarter\.com/projects/(.*?)/(.*?)/widget/video\.html},
    ]
  end

  def oembed_url
    @oembed_url ||= "https://www.kickstarter.com/services/oembed"
  end

  def oembed_params
    {url: canonical_url, format: "json"}
  end

  def type
    "video"
  end

  def canonical_url
    "https://www.kickstarter.com/projects/#{embed_url_data[1]}/#{embed_url_data[2]}"
  end

  def image_url
    @image_url ||= begin
      page = URLCache.new(canonical_url).body
      doc = Nokogiri::HTML5(page)
      image = doc.css("meta[property='og:image']")
      if image.empty?
        super
      else
        url = image.first.attributes["content"].value
      end
    end
  end
end
