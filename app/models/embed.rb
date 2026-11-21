class Embed < ApplicationRecord
  # A video's parent is its channel. The source condition lets the lookup use
  # index_embeds_on_source_and_provider_id; on provider_id alone it reads the
  # whole table.
  belongs_to :parent, -> { youtube_channel }, class_name: "Embed", foreign_key: :parent_id, primary_key: :provider_id

  # The channel's avatar row. The join rides
  # index_images_on_provider_and_provider_id. Meaningful on youtube_channel
  # rows only: a video's provider_id is a video id, which no embed_icon row
  # carries.
  # No dependent option on purpose: the row keys on the channel identity,
  # not on this embed, and it outlives any one embed row.
  has_one :channel_image, -> { provider_embed_icon },
    class_name: "Image", foreign_key: :provider_id, primary_key: :provider_id,
    inverse_of: false

  enum :source, {youtube_video: 0, youtube_channel: 1}

  # Stores YouTube API items and returns the provider ids of the ones whose
  # data changed. The rest are left untouched: live streams are refetched
  # hourly, and an unchanged answer must not look like an edit.
  def self.store_youtube(videos:, channels:)
    embeds = videos.map { new(source: :youtube_video, provider_id: it["id"], parent_id: it.safe_dig("snippet", "channelId"), data: it) } +
      channels.map { new(source: :youtube_channel, provider_id: it["id"], data: it) }
    return [] if embeds.empty?

    # Scoped by source so each half rides index_embeds_on_source_and_provider_id;
    # provider_id alone is a parallel scan of the whole table.
    ids = embeds.group_by(&:source).transform_values { it.map(&:provider_id) }
    stored = ids.map { |source, provider_ids| where(source:, provider_id: provider_ids) }.reduce(:or)
      .pluck(:source, :provider_id, :data)
      .to_h { |source, provider_id, data| [[source, provider_id], data] }
    changed = embeds.reject { stored[[it.source, it.provider_id]] == it.data }
    import(changed, on_duplicate_key_update: {conflict_target: [:source, :provider_id], columns: [:data]}) if changed.present?
    changed.map(&:provider_id)
  end

  def channel
    youtube_video? && self.class.youtube_channel.find_by_provider_id(parent_id)
  end

  def duration_in_seconds
    return unless duration = data.safe_dig("contentDetails", "duration")

    parts = duration.match(/^
      (?<sign>\+|-)?
      P(?:
        (?:
          (?:(?<years>\d+)Y)?
          (?:(?<months>\d+)M)?
          (?:(?<days>\d+)D)?
          (?<time>T
            (?:(?<hours>\d+(?:[.,]\d+)?)H)?
            (?:(?<minutes>\d+(?:[.,]\d+)?)M)?
            (?:(?<seconds>\d+(?:[.,]\d+)?)S)?
          )?
        ) |
        (?<weeks>\d+(?:[.,]\d+)?W)
      )
    $/x)

    parts = parts.named_captures.transform_values(&:to_i)

    (((((parts["weeks"] * 7) + parts["days"]) * 24 + parts["hours"]) * 60) + parts["minutes"]) * 60 + parts["seconds"]
  end

  def chapters
    text = data.safe_dig("snippet", "description") || ""
    @chapters ||= TextToChapters.call(text, duration_in_seconds)
  end

  def live_broadcast_content
    data.safe_dig("snippet", "liveBroadcastContent")
  end

  def scheduled_start_time
    data.safe_dig("liveStreamingDetails", "scheduledStartTime")
  end

  def scheduled_time
    Time.parse(scheduled_start_time) if scheduled_start_time
  end

  def actual_start_time
    value = data.safe_dig("liveStreamingDetails", "actualStartTime")
    Time.parse(value) if value
  end

  def actual_end_time
    value = data.safe_dig("liveStreamingDetails", "actualEndTime")
    Time.parse(value) if value
  end

  # When a stream was due to start, or started if it went live unscheduled.
  def start_time
    scheduled_time || actual_start_time
  end

  # Upcoming or live, until the stream ends, for up to a day after it started
  # or was due to.
  def unfinished_stream?
    live_broadcast_content != "none" &&
      actual_end_time.nil? &&
      start_time.present? &&
      start_time >= 24.hours.ago
  end
end
