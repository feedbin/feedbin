module FaviconCrawler
  class Build
    include Sidekiq::Worker
    sidekiq_options retry: false

    def perform(host, force = false)
      @host = host
      @force = force

      urls = find_meta_links(["icon", "shortcut icon"]).push(default_favicon_location)

      image = ImageCrawler::Image.new(id: "#{SecureRandom.hex}-favicon", preset_name: "favicon", image_urls: urls, favicon_host: @host, icon_provider: "favicon")
      ImageCrawler::Pipeline::Find.perform_async(image.to_h)

      urls = find_meta_links(["apple-touch-icon", "apple-touch-icon-precomposed"])
      if urls.present?
        image = ImageCrawler::Image.new(id: "#{SecureRandom.hex}-touch-icon", preset_name: "favicon", image_urls: urls, favicon_host: @host, icon_provider: "touch_icon")
        ImageCrawler::Pipeline::Find.perform_async(image.to_h)
      end
    end

    def find_meta_links(names)
      return [] unless document.present?
      links = document.search(xpath(names))
      links.map do |element|
        Addressable::URI.join(homepage.uri.to_s, element["href"]).to_s
      end
    end

    def document
      return @document if defined?(@document)
      @document = Nokogiri::HTML5(homepage)
    rescue => exception
      Sidekiq.logger.info "find_meta_links exception=#{exception.inspect} host=#{@host}"
      @document = nil
    end

    def homepage
      return @homepage if defined?(@homepage)
      url = URI::HTTP.build(host: @host)
      HTTP.timeout(write: 5, connect: 5, read: 5).follow.get(url)
    rescue => exception
      Sidekiq.logger.info "homepage exception=#{exception.inspect} host=#{@host}"
      @homepage = nil
    end

    def default_favicon_location
      URI::HTTP.build(host: @host, path: "/favicon.ico")
    end

    def should_update?
      return true if @force
      return false if updated_recently?
      true
    end

    def updated_recently?
      Icon.provider_favicon.where(provider_id: @host)&.updated_at&.after?(1.hour.ago)
    end

    def xpath(names)
      names.map do |name|
        "//link[not(@mask) and translate(@rel, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz') = '#{name}']"
      end.join(" | ")
    end
  end
end