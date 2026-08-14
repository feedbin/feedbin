module FaviconCrawler
  class Finder
    include Sidekiq::Worker
    sidekiq_options retry: false

    ICON_NAMES = ["shortcut icon", "icon", "apple-touch-icon", "apple-touch-icon-precomposed"]
    TOUCH_ICON_NAMES = ["apple-touch-icon", "apple-touch-icon-precomposed"]

    def perform(host, force = false)
      @favicon = Favicon.unscoped.where(host: host).first_or_initialize
      @force = force
      update if should_update?
    end

    private

    def update
      downloaded = []
      new_favicon = nil
      all_favicon_urls.each do |url|
        response = download_favicon(url)
        next if response.blank?
        downloaded.push(response.path)
        break if response.not_modified?
        resized = Image.resize(response.path)
        next if resized.blank?
        downloaded.push(resized)

        new_favicon = {resized: resized, original: response.path, response: response}

        break
      end

      return unless new_favicon.present?

      processor = Processor.new(new_favicon, @favicon.host)
      if @force || @favicon.data["favicon_hash"] != processor.favicon_hash
        processor.call
        return if processor.favicon_url.nil?
        @favicon.favicon = processor.encoded_favicon
        @favicon.url = processor.favicon_url
        @favicon.data = {
          "favicon_hash"  => processor.favicon_hash,
          "Etag"          => new_favicon[:response].etag,
          "Last-Modified" => new_favicon[:response].last_modified
        }
        Librato.increment("favicon.updated")
      end

      @favicon.save
    # Every url that got as far as a file on disk, not just the one that won:
    # a candidate rejected for being unreadable, or a 304 arriving before any
    # resize, has already been written to the worker's tmpdir by then.
    ensure
      downloaded.each do |file|
        File.unlink(file)
      rescue Errno::ENOENT
      end
    end

    # Parsed once and memoized including the failure case: all_favicon_urls and
    # touch_icon_urls both derive from it, and re-deriving would mean a second
    # homepage fetch per crawl. `defined?` rather than ||= so an empty result
    # is not re-attempted.
    def icon_links
      return @icon_links if defined?(@icon_links)
      @icon_links = begin
        homepage = download_homepage
        Nokogiri::HTML5(homepage.to_s).search(xpath)
          .reject {
            it["href"].to_s.strip.empty?
          }
          .sort_by {
            -(it["sizes"] ? it["sizes"].scan(/\d+/).first.to_i : 0)
          }
          .sort_by {
            it["media"] && it["media"].include?("dark") ? 1 : 0
          }
          .sort_by {
            rel = it["rel"].to_s.strip.downcase
            index = ICON_NAMES.index(rel)
            index.nil? ? ICON_NAMES.length : index
          }
          .map {
            [it["rel"].to_s.strip.downcase, Addressable::URI.join(homepage.uri, it["href"])]
          }
      rescue => exception
        Sidekiq.logger.info "find_meta_links exception=#{exception.inspect} host=#{@favicon.host}"
        []
      end
    end

    def all_favicon_urls
      icon_links.map(&:last).push(default_favicon_location)
    end

    # No default_favicon_location fallback here, unlike all_favicon_urls: every
    # host has a /favicon.ico worth guessing at, and none has a guessable touch
    # icon. A host that advertises none simply has none.
    def touch_icon_urls
      icon_links.filter_map { |rel, url| url if TOUCH_ICON_NAMES.include?(rel) }
    end

    def default_favicon_location
      URI::HTTP.build(host: @favicon.host, path: "/favicon.ico")
    end

    def download_homepage
      url = URI::HTTP.build(host: @favicon.host)
      HTTP.timeout(write: 5, connect: 5, read: 5).follow.get(url)
    end

    def download_favicon(url)
      options = {}.tap do |hash|
        hash[:user_agent] = "Mozilla/5.0"
        # unless @force
        #   hash[:etag]          = @favicon.data["Etag"]
        #   hash[:last_modified] = @favicon.data["Last-Modified"]
        # end
      end
      Feedkit::Request.download(url.to_s, **options)
    rescue Feedkit::Error => exception
      Sidekiq.logger.info "download_favicon exception=#{exception.inspect} url=#{url}"
      nil
    end

    def should_update?
      return true if @force
      !updated_recently?
    end

    def updated_recently?
      @favicon.updated_at && @favicon.updated_at.after?(1.hour.ago)
    end

    def xpath
      icon_names = ICON_NAMES.map { |icon_name|
        "//link[not(@mask) and translate(@rel, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz') = '#{icon_name}']"
      }
      icon_names.join(" | ")
    end
  end
end