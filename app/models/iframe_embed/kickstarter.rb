class IframeEmbed::Kickstarter < IframeEmbed

  def self.supported_urls
    [
      %r(https?://www\.kickstarter\.com/projects/(.*?)/(.*?)/widget/video\.html)
    ]
  end

  def oembed_url
    @oembed_url ||= "https://www.kickstarter.com/services/oembed"
  end

  def oembed_params
    {url: url_param, format: "json"}
  end

  def type
    "video"
  end

  def image_url
    @image_url ||= begin
      page = URLCache.new(url_param).body
      doc = Nokogiri::HTML5(page)
      image = doc.css("meta[property='og:image']")
      if image.empty?
        super
      else
        url = image.first.attributes["content"].value
      end
    end
  end

  private

    def url_param
      "https://www.kickstarter.com/projects/#{embed_url_data[1]}/#{embed_url_data[2]}"
    end

end