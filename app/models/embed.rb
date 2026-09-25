class Embed < ApplicationRecord
  belongs_to :parent, class_name: "Embed", foreign_key: :parent_id, primary_key: :provider_id

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
end
