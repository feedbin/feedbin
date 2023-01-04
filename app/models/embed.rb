class Embed < ApplicationRecord
  belongs_to :parent, class_name: "Embed", foreign_key: "parent_id"
  enum source: {youtube_video: 0, youtube_channel: 1, twitter_user: 2}

  after_commit :update_icon, on: [:create, :update]

  def channel
    youtube_video? && self.class.youtube_channel.find_by_provider_id(parent_id)
  end

  def duration_in_seconds
    return unless youtube_video?
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

  def icon_url
    return unless youtube_channel?
    data.safe_dig("snippet", "thumbnails", "high", "url")
  end

  private

  def update_icon
    return unless youtube_channel?
    IconCrawler::Provider::Youtube.new.perform(provider_id)
  end

end
