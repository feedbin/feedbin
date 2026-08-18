# One-time: populates feeds.channel_id for feeds that already exist. New and
# re-crawled feeds get it from Feed#set_channel_id, but a feed that is not
# crawled again for hours would render no channel avatar until it was, and the
# harvest that stores the avatar does not wait for that.
#
# Also the repair pass for rows an earlier derivation got wrong: channel
# feeds serve the feed-level yt:channelId bare, and until canonical_channel_id
# restored the UC prefix, every crawled YouTube feed stored the 22-character
# suffix -- a key no images row matches. Those rows are not nil, so the scan
# recomputes for every candidate and writes only what changed.
#
# update_column, not update: channel_id is part of no view, and bumping
# updated_at on every YouTube feed at once would invalidate the sidebar and
# every entry list referencing them for a change nobody can see.
class BackfillFeedChannelIds
  include Sidekiq::Worker
  sidekiq_options queue: :utility

  def perform
    candidates.find_each do |feed|
      value = feed.derived_channel_id
      next if value.blank? || value == feed.channel_id
      feed.update_column(:channel_id, value)

      # The avatar for this channel may have landed while the key was wrong,
      # in which case ChannelImage's touch matched nothing and no other write
      # is coming -- the sidebar and entry caches reach the avatar only
      # through feed.updated_at, so without this the repair stays invisible.
      # A feed whose avatar has not been harvested keeps the quiet write; its
      # touch arrives with the image.
      feed.touch if Image.provider_embed_icon.exists?(provider_id: value)
    end
  end

  # Both sources the derivation reads, so the scan does not have to visit
  # every feed row. Bound conditions, never interpolation -- the LIKE pattern
  # contains a "?" of its own.
  def candidates
    from_url    = Feed.where("feed_url LIKE ?", "%youtube.com/feeds/videos.xml?channel_id=%")
    from_parsed = Feed.where("options->>'youtube_channel_id' IS NOT NULL")
    from_url.or(from_parsed)
  end
end
