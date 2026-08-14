# One-time: populates feeds.channel_id for feeds that already exist. New and
# re-crawled feeds get it from Feed#set_channel_id, but a feed that is not
# crawled again for hours would render no channel avatar until it was, and the
# harvest that stores the avatar does not wait for that.
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
      next if value.blank?
      feed.update_column(:channel_id, value)
    end
  end

  # Both sources the derivation reads, so the scan does not have to visit
  # every feed row. Bound conditions, never interpolation -- the LIKE pattern
  # contains a "?" of its own.
  def candidates
    from_url    = Feed.where("feed_url LIKE ?", "%youtube.com/feeds/videos.xml?channel_id=%")
    from_parsed = Feed.where("options->>'youtube_channel_id' IS NOT NULL")
    from_url.or(from_parsed).where(channel_id: nil)
  end
end
