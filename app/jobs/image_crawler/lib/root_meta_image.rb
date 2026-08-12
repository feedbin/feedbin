module ImageCrawler
  # An og:image that a host serves for its root page is site branding, not
  # article art. Candidates matching it are skipped so every entry in a feed
  # does not end up with the same generic image.
  class RootMetaImage
    CACHE_TTL = 7 * 24 * 60 * 60

    def self.site_wide?(candidate_url, page_url)
      new(page_url).site_wide?(candidate_url)
    end

    def initialize(page_url)
      @page_url = begin
        parsed = Addressable::URI.heuristic_parse(page_url.to_s)
        parsed&.host.nil? ? nil : parsed
      rescue Addressable::URI::InvalidURIError
        nil
      end
    end

    def site_wide?(candidate_url)
      return false if @page_url.nil?
      return false if root_page?
      root_urls.include?(candidate_url.to_s)
    end

    private

    def root_page?
      ["", "/"].include?(@page_url.path.to_s) && @page_url.query.nil?
    end

    def root_urls
      cached = Cache.read(cache_key)
      return cached[:urls] || [] if cached[:checked]

      urls = download
      Cache.write(cache_key, {checked: true, urls: urls}, options: {expires_in: CACHE_TTL})
      urls
    end

    def download
      file = Down.download(root_url, max_size: 5 * 1024 * 1024)
      MetaImages.parse_meta_urls(file.read, root_url).map(&:to_s)
    rescue Down::Error
      []
    end

    def root_url
      @root_url ||= Addressable::URI.new(scheme: @page_url.scheme || "https", host: @page_url.host).to_s
    end

    def cache_key
      "root_meta_image_#{Digest::SHA1.hexdigest(@page_url.host)}"
    end
  end
end
