module ImageCrawler
  # Rejects boilerplate preview candidates. Only meta-derived candidates
  # (og:image / twitter:image) are policed — inline images and attached media
  # legitimately repeat within a feed (retweet chains, reposts).
  class ReuseRules
    def self.enabled?
      ENV["IMAGE_REUSE_RULES"].present?
    end

    def initialize(image)
      @image = image
    end

    # Pre-download check: another entry in this feed already uses the
    # candidate url, or it is the host's site-wide og:image. The feed check
    # runs first — it is one indexed query, while the site-wide check may
    # fetch the host's root page.
    def skip?(original_url)
      return false unless self.class.enabled?
      return false unless meta_candidate?(original_url)

      used_in_feed?(original_url) || site_wide?(original_url)
    end

    # Post-process check: same image bytes (different url) already used by
    # another entry in this feed. Catches cache-busted site-wide images.
    def fingerprint_used_in_feed?(fingerprint)
      return false unless self.class.enabled?
      return false unless meta_candidate?(@image.original_url)
      return false if @image.feed_id.nil?

      ::Image.entry_images
        .where(feed_id: @image.feed_id, image_fingerprint: fingerprint)
        .where.not(provider_id: @image.provider_id.to_s)
        .exists?
    end

    private

    def meta_candidate?(url)
      (@image.meta_image_urls || []).include?(url.to_s)
    end

    def site_wide?(url)
      RootMetaImage.site_wide?(url, @image.page_url)
    end

    def used_in_feed?(url)
      return false if @image.feed_id.nil?

      ::Image.entry_images
        .where(feed_id: @image.feed_id, url_fingerprint: ::Image.url_fingerprint_for(url))
        .where.not(provider_id: @image.provider_id.to_s)
        .exists?
    end
  end
end
