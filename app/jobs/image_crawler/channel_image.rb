module ImageCrawler
  class ChannelImage
    include Sidekiq::Worker
    sidekiq_options retry: false

    SUFFIX = "-channel".freeze

    # Largest first. The channels API returns default (88x88), medium
    # (240x240) and high (800x800); the avatar is hotlinked from default
    # today, which is soft in every slot bigger than a favicon.
    THUMBNAIL_SIZES = %w[high medium default].freeze

    # Scoped to the channel: one row serves the channel's own feed and every
    # playlist entry from that channel. feed_id stays nil -- a channel has no
    # single feed, and feed_id only feeds ReuseRules, which a
    # content-addressed preset never reaches.
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

    # Cache invalidation: the sidebar and entry keys include the feed, not
    # this row, so feeds rendering the channel must be touched. Bounded -- a
    # channel has one feed, occasionally a few url spellings. Only reached
    # when the bytes changed (unchanged? returns before Process otherwise).
    def perform(id, image)
      return if image["storage_path"].blank?

      # Never fall through to a nil query: channel_id is null for every
      # non-YouTube feed, and touching all of those is the fan-out this
      # design avoids. Blank payload = pre-provider_id deploy; skip, the
      # next harvest self-heals.
      channel_id = image["provider_id"]
      return if channel_id.blank?

      Feed.where(channel_id: channel_id).find_each(&:touch)
    end
  end
end
