module FaviconCrawler
  class Finder
    include Sidekiq::Worker
    sidekiq_options retry: false

    def perform(host, force = false)
      @favicon = Favicon.unscoped.where(host: host).first_or_initialize
      @force = force
      update if should_update?
    end

    private

    def update
      favicon_found = false
      response = nil

      favicon_url = find_meta_links
      if favicon_url
        response = download_favicon(favicon_url)
        favicon_found = true unless response.nil?
      end

      unless favicon_found
        favicon_url = default_favicon_location
        response = download_favicon(favicon_url)
      end

      if response
        processor = Processor.new(response.path, @favicon.host)
        if @force || @favicon.data["favicon_hash"] != processor.favicon_hash
          processor.process
          return if processor.favicon_url.nil?
          @favicon.favicon = processor.encoded_favicon
          @favicon.url = processor.favicon_url
          @favicon.data = {
            "favicon_hash"  => processor.favicon_hash,
            "Etag"          => response.etag,
            "Last-Modified" => response.last_modified
          }
          Librato.increment("favicon.updated")
        end
      end

      @favicon.save
    ensure
      if response.respond_to?(:path)
        File.unlink(response.path) rescue Errno::ENOENT
      end
    end

    def find_meta_links
      favicon_url = nil
      homepage = download_homepage
      html = Nokogiri::HTML5(homepage)
      favicon_links = html.search(xpath)
      if favicon_links.present?
        favicon_url = favicon_links.first.to_s
        favicon_url = URI.parse(favicon_url)
        favicon_url.scheme = "http"
        unless favicon_url.host
          favicon_url = URI::HTTP.build(scheme: "http", host: @favicon.host)
          favicon_url = favicon_url.merge(favicon_links.last.to_s)
        end
      end
      favicon_url
    rescue => exception
      Sidekiq.logger.info "find_meta_links exception=#{exception.inspect} host=#{@favicon.host}"
      nil
    end

    def default_favicon_location
      URI::HTTP.build(host: @favicon.host, path: "/favicon.ico")
    end

    def download_homepage
      url = URI::HTTP.build(host: @favicon.host)
      response = HTTP
        .timeout(write: 5, connect: 5, read: 5)
        .follow
        .get(url)
        .to_s
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
      icon_names = ["shortcut icon", "icon", "apple-touch-icon", "apple-touch-icon-precomposed"]
      icon_names = icon_names.map { |icon_name|
        "//link[not(@mask) and translate(@rel, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz') = '#{icon_name}']/@href"
      }
      icon_names.join(" | ")
    end
  end
end