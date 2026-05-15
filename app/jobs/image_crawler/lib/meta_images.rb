module ImageCrawler
  class MetaImages
    def initialize(url)
      @url = url
    end

    def self.find_urls(url)
      new(url).find_urls
    rescue Addressable::URI::InvalidURIError
      []
    end

    def find_urls
      if cache.urls
        Librato.increment("meta_images", source: "cached")
        cache.urls
      elsif needs_download?
        Librato.increment("meta_images", source: "download")
        download
      else
        Librato.increment("meta_images", source: "skip")
      end
    end

    def download
      urls = []
      file = Down.download(parsed_url, max_size: 5 * 1024 * 1024)
      urls = parse(file)
    rescue Down::Error => exception
      Sidekiq.logger.info "PageImages: exception=#{exception.inspect} url=#{@url}"
      urls
    ensure
      cache.save({checked: true, urls: urls})
      cache.has_meta!(!urls.empty?)
    end

    def parse(file)
      Nokogiri.HTML5(file.read).search("meta[property='twitter:image'], meta[property='og:image']").map do |element|
        url = element["content"]&.strip
        next if url.nil?
        next if url == ""
        Addressable::URI.join(parsed_url, url)
      end.compact
    end

    def needs_download?
      !cache.checked? && cache.has_meta?
    end

    def cache
      @cache ||= MetaImagesCache.new(parsed_url)
    end

    def parsed_url
      @parsed_url ||= begin
        parsed = Addressable::URI.parse(@url)
        raise Addressable::URI::InvalidURIError if parsed.host.nil?
        parsed
      end
    end
  end
end
