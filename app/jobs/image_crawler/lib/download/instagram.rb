module ImageCrawler
  class Download::Instagram < Download
    def self.supported_urls
      [
        %r{.*?//www\.instagram\.com/p/(.*?)(/|#|\?|$)},
        %r{.*?//instagram\.com/p/(.*?)(/|#|\?|$)}
      ]
    end

    def download
      download_file(image_url)
    rescue Down::Error => exception
    end

    def image_url
      data.safe_dig("thumbnail_url")
    end

    private

    OEMBED_URL = "https://graph.facebook.com/v9.0/instagram_oembed"

    def data
      @data ||= begin
        options = {
          params: {
            access_token: ENV["FACEBOOK_ACCESS_TOKEN"],
            url: "https://instagram.com/p/#{provider_identifier}",
            fields: "thumbnail_url"
          }
        }
        JSON.load(HTTP.get(OEMBED_URL, options).to_s)
      end
    end
  end
end