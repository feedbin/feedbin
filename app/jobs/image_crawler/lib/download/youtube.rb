module ImageCrawler
  class Download::Youtube < Download
    attr_reader :image_url

    # Largest first. maxresdefault is the only 16:9 size — sddefault and
    # hqdefault are 4:3 with letterbox bars baked in — but it does not exist
    # for every video, so the smaller sizes stay as fallbacks.
    SIZES = %w[maxresdefault sddefault hqdefault]

    # Thumbnail URLs, so a publisher's og:image pointing straight at a
    # specific size still goes through the ladder above instead of being
    # taken at face value.
    THUMBNAIL_URLS = [
      %r{//i\d*\.ytimg\.com/vi(?:_webp)?/([^/]+)/},
      %r{//img\.youtube\.com/vi(?:_webp)?/([^/]+)/}
    ]

    def self.supported_urls
      Feedbin::Application.config.youtube_embed_urls + THUMBNAIL_URLS
    end

    def download
      SIZES.each do |option|
        @image_url = "https://i.ytimg.com/vi/#{provider_identifier}/#{option}.jpg"
        download_file(@image_url)
        break
      rescue Feedkit::Error
      end
    end
  end
end
