module ImageCrawler
  class Download::Youtube < Download
    attr_reader :image_url

    def self.supported_urls
      Feedbin::Application.config.youtube_embed_urls
    end

    def download
      ["maxresdefault", "hqdefault"].each do |option|
        @image_url = "https://i.ytimg.com/vi/#{provider_identifier}/#{option}.jpg"
        download_file(@image_url)
        break
      rescue Down::Error => exception
      end
    end
  end
end
