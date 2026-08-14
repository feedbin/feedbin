module ImageCrawler
  class ChannelImage
    include Sidekiq::Worker
    sidekiq_options retry: false

    SUFFIX = "-channel".freeze

    # Largest first. The channels API returns default (88x88), medium
    # (240x240) and high (800x800); the avatar is hotlinked from default
    # today, which is soft in every slot bigger than a favicon.
    THUMBNAIL_SIZES = %w[high medium default].freeze

    # Scoped to the channel, not to a feed and not to an entry: one row serves
    # the channel's own feed and every playlist entry from that channel, which
    # is the case that motivated splitting feed-level from entry-level in the
    # first place. feed_id is left nil for the same reason -- a channel has no
    # single feed, and feed_id only feeds ReuseRules, which a content-addressed
    # preset never reaches.
    def self.schedule(channel)
      url = THUMBNAIL_SIZES.filter_map { channel.data.safe_dig("snippet", "thumbnails", it, "url") }.first
      return if url.blank?

      image = Image.new_with_attributes(
        id: "#{channel.provider_id}#{SUFFIX}",
        preset_name: "channel_avatar",
        image_urls: [url],
        provider: ::Image.providers[:embed_icon],
        provider_id: channel.provider_id
      )
      Pipeline::Find.perform_async(image.to_h)
    end

    # Nothing is written onto a feed: the row is keyed by the channel and
    # Feed#icon_url reads it. What is left is cache invalidation -- the
    # sidebar's key and entries_cache_key both include the feed, not the icon
    # row, so a feed rendering this channel keeps serving the old avatar
    # unless it is touched. Bounded by design (a channel has one feed,
    # occasionally a few url spellings of it), which is why this is a touch
    # rather than a digest change; the fan-out this design exists to kill is
    # the 100,000-row medium.com favicon case, not this.
    #
    # Only reached when the bytes actually changed: Pipeline::Find's
    # unchanged? short circuit returns before Process for a re-crawl of the
    # same avatar, so an unchanged channel costs no invalidation.
    def perform(id, image)
      return if image["storage_path"].blank?

      # delete_suffix, not split("-").first as the other tenants do: a
      # YouTube channel id is base64url, so "-" and "_" are ordinary
      # characters in it and UC-lHJZR3Gqxm24_Vd_AJ5Yw would come back as "UC".
      Feed.where(channel_id: id.delete_suffix(SUFFIX)).find_each(&:touch)
    end
  end
end
