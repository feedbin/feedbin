# One-time: populates feeds.channel_id for existing feeds (new and
# re-crawled feeds get it from Feed#set_channel_id) and repairs rows that
# stored the bare 22-character suffix. Recomputes per candidate, writes only
# what changed. update_column: bumping updated_at on every YouTube feed at
# once would invalidate caches for a change nobody can see.
class BackfillFeedChannelIds
  include Sidekiq::Worker
  sidekiq_options queue: :utility

  def perform
    candidates.find_each do |feed|
      value = feed.derived_channel_id
      next if value.blank? || value == feed.channel_id
      feed.update_column(:channel_id, value)

      # If the avatar already landed, ChannelImage's touch matched nothing
      # and no other write is coming -- caches reach the avatar only through
      # feed.updated_at, so touch here. No avatar yet: keep the quiet write,
      # the touch arrives with the image.
      feed.touch if Image.provider_embed_icon.exists?(provider_id: value)
    end
  end

  # Both sources the derivation reads, so the scan skips non-YouTube feeds.
  # Bound conditions -- the LIKE pattern contains a "?" of its own.
  def candidates
    from_url    = Feed.where("feed_url LIKE ?", "%youtube.com/feeds/videos.xml?channel_id=%")
    from_parsed = Feed.where("options->>'youtube_channel_id' IS NOT NULL")
    from_url.or(from_parsed)
  end
end
