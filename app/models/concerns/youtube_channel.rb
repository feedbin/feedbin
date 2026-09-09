# Feed's YouTube behavior: channel id derivation, the WebSub rewrites, and
# the avatar row. Two derivations on purpose: derived_channel_id (wide)
# answers "which channel do this feed's videos come from" and feeds the
# channel_id column; youtube_channel_id (strict) answers "is this the
# canonical feed whose self_url and hub we rewrite" and requires feed_url
# and self_url to agree.
module YoutubeChannel
  extend ActiveSupport::Concern

  # Multiple prefixes wrap the same 22-character identity (UC the channel,
  # UU/UULF/UUSH its playlists); a channel_id= url always carries UC-form.
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

  # The channel feed serves the feed-level yt:channelId bare; everything
  # else speaks UC-form, so restore the prefix. Keyed on length, not prefix:
  # a bare id can itself begin with "UC".
  def canonical_channel_id(value)
    return value unless value&.length == ID_SUFFIX_LENGTH
    "UC#{value}"
  end

  # Fallback for feeds not yet crawled or parsed.
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
