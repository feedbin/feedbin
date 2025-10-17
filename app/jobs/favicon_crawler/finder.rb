module FaviconCrawler
  class Finder
    include Sidekiq::Worker
    sidekiq_options retry: false

    ICON_NAMES = ["shortcut icon", "icon", "apple-touch-icon", "apple-touch-icon-precomposed"]

    def perform(host, force = false)
      @favicon = Favicon.unscoped.where(host: host).first_or_initialize
      @force = force
      update if should_update?
    end

    private

    def update
      new_favicon = nil
      all_favicon_urls.each do |url|
        response = download_favicon(url)
        next if response.blank?
        resized = Image.resize(response.path)
        next if resized.blank?

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
    ensure
      File.unlink(favicon[:original]) rescue Errno::ENOENT
      File.unlink(favicon[:resized]) rescue Errno::ENOENT
    end

    def all_favicon_urls
      homepage = download_homepage
      links = Nokogiri::HTML5(homepage.to_s).search(xpath)

      links = links.reject {
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

      urls = links.map do |link|
        Addressable::URI.join(homepage.uri, link["href"])
      end

      urls.push(default_favicon_location)
    rescue => exception
      Sidekiq.logger.info "find_meta_links exception=#{exception.inspect} host=#{@favicon.host}"
      nil
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
        unless @force
          hash[:etag]          = @favicon.data["Etag"]
          hash[:last_modified] = @favicon.data["Last-Modified"]
        end
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