# Everything Feed knows about being a YouTube channel feed, in one place:
# deriving the channel id, the WebSub rewrites that depend on it, and the
# avatar row keyed by it.
#
# Two derivations on purpose, answering different questions:
#
# - +derived_channel_id+ (wide) -- "which channel do this feed's videos come
#   from?" Feeds the +channel_id+ column so a channel avatar harvested once
#   can find every feed that renders it. The parsed feed-level value wins,
#   falling back to the feed url for feeds not yet crawled.
#
# - +youtube_channel_id+ (strict) -- "is this the canonical channel feed
#   whose self_url and hub we rewrite?" Requires feed_url and self_url to
#   agree, which is the right guard for WebSub and the wrong one for icon
#   resolution.
module YoutubeChannel
  extend ActiveSupport::Concern

  # The one url shape both derivations read. Multiple prefixes wrap the same
  # 22-character identity (UC the channel, UU/UULF/UUSH its playlists), but a
  # subscription by channel_id always carries UC-form here.
  CHANNEL_FEED_URL = %r{\Ahttps?://(?:www\.)?youtube\.com/feeds/videos\.xml\?channel_id=([^#?&]+)}

  # The identity is the 22 characters after the container prefix.
  ID_SUFFIX_LENGTH = 22

  included do
    # One avatar row shared by every feed for the channel -- channel-keyed,
    # unlike icon_image_record, which is this feed's alone.
    has_one :channel_image_record, -> { provider_embed_icon }, class_name: "Image", foreign_key: :provider_id, primary_key: :channel_id

    before_save :set_hubs
    before_save :set_channel_id
    after_commit :update_youtube_videos, on: :create
  end

  def derived_channel_id
    canonical_channel_id(options.safe_dig("youtube_channel_id").presence || channel_id_from_feed_url)
  end

  def youtube_channel_id
    return nil unless self[:self_url]&.match?(CHANNEL_FEED_URL)
    channel_id_from_feed_url
  end

  def self_url
    if youtube_channel_id
      "https://www.youtube.com/xml/feeds/videos.xml?channel_id=#{youtube_channel_id}"
    else
      self[:self_url]
    end
  end

  def known_hubs
    if youtube_channel_id
      ["https://pubsubhubbub.appspot.com"]
    end
  end

  private

  # The channel feed is the only place the feed-level yt:channelId arrives
  # bare -- playlist feeds, entry-level ids, and the Data API all speak
  # UC-form, and images.provider_id is keyed on it -- so restore the prefix.
  # Keyed on length, not prefix: a bare id can itself begin with "UC", and if
  # YouTube ever serves the channel feed in UC-form it passes through
  # untouched.
  def canonical_channel_id(value)
    return value unless value&.length == ID_SUFFIX_LENGTH
    "UC#{value}"
  end

  # The fallback for a feed that has not been crawled since feedkit started
  # surfacing the parsed value, and for a brand-new feed not yet parsed at all.
  def channel_id_from_feed_url
    return nil if feed_url.blank?
    match = feed_url.match(CHANNEL_FEED_URL)
    match && match[1]
  end

  def set_channel_id
    self[:channel_id] = derived_channel_id
  end

  def set_hubs
    if known_hubs.present?
      self[:hubs] = known_hubs
    end
  end

  def update_youtube_videos
    if youtube_channel_id
      FeedCrawler::UpdateYoutubeVideos.perform_in(2.minutes, id)
    end
  end
end
