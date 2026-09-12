module FaviconCrawler
  class Finder
    include Sidekiq::Worker
    sidekiq_options retry: false

    ICON_NAMES = ["shortcut icon", "icon", "apple-touch-icon", "apple-touch-icon-precomposed"]
    TOUCH_ICON_NAMES = ["apple-touch-icon", "apple-touch-icon-precomposed"]

    # At most one crawl per host per hour, whatever the number of subscribe
    # events. A Redis key rather than a row timestamp: images.updated_at is
    # a content version that moves only when the bytes move, so it cannot
    # say when a host was last checked, and the favicons row is no longer
    # written.
    GATE = 1.hour

    # force skips the gate: the manual refresh in settings passes true. The
    # pipeline still decides on bytes, so force never re-uploads an
    # unchanged icon. critical false keeps a caller's pipeline stages off
    # the critical queues; nothing passes it today, it exists so a future
    # sweep cannot land on the critical queues by omission.
    def perform(host, force = false, critical = true)
      @host = host.to_s.downcase
      return if @host.blank?

      unless force || RedisLock.acquire("favicon_crawl:#{@host}", GATE.to_i)
        Librato.increment("favicon.gated")
        return
      end

      schedule_icon("favicon", ::Image.providers[:website_favicon], all_favicon_urls, critical)
      schedule_icon("touch_icon", ::Image.providers[:website_touch_icon], touch_icon_urls, critical)
      Librato.increment("favicon.crawl")
    end

    private

    # Two schedules because the presets render at different sizes from
    # different candidate lists, and they must stay separate providers
    # (Pipeline::Find#unchanged? keys on the row's original_fingerprint).
    # The pipeline walks the candidates in order and decides on bytes; the
    # crawler downloads nothing itself.
    def schedule_icon(preset_name, provider, urls, critical)
      # .uniq(&:to_s): the list mixes Addressable::URI and URI::HTTP --
      # equal by string, distinct classes, invisible to a bare .uniq.
      urls = urls.uniq(&:to_s)
      return if urls.empty?

      # Both presets are pictures of the site; only the rendering differs.
      image = ImageCrawler::Image.new_with_attributes(
        id: "#{@host}-#{preset_name}",
        kind: ::Image.kinds[:site_icon],
        preset_name: preset_name,
        image_urls: urls.map(&:to_s),
        provider: provider,
        provider_id: @host,
        critical: critical
      )
      ImageCrawler::Pipeline::Find.perform_async(image.to_h)
    end

    # Memoized with `defined?` so a failed parse is not re-fetched.
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
        Sidekiq.logger.info "find_meta_links exception=#{exception.inspect} host=#{@host}"
        []
      end
    end

    def all_favicon_urls
      icon_links.map(&:last).push(default_favicon_location)
    end

    # No guessed fallback: /favicon.ico is worth trying, a touch icon
    # location is not. A host that advertises none has none.
    def touch_icon_urls
      icon_links.filter_map { |rel, url| url if TOUCH_ICON_NAMES.include?(rel) }
    end

    def default_favicon_location
      URI::HTTP.build(host: @host, path: "/favicon.ico")
    end

    def download_homepage
      url = URI::HTTP.build(host: @host)
      HTTP.timeout(write: 5, connect: 5, read: 5).follow.get(url)
    end

    def xpath
      icon_names = ICON_NAMES.map { |icon_name|
        "//link[not(@mask) and translate(@rel, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz') = '#{icon_name}']"
      }
      icon_names.join(" | ")
    end
  end
end
