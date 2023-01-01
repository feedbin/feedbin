class BackfillProviderIds
  include Sidekiq::Worker
  include SidekiqHelper
  sidekiq_options queue: :utility

  def perform(batch)
    ids = build_ids(batch)
    entries = Entry.where(id: ids).select(:id, :data, :main_tweet_id)

    provider_parent_id_data = {}
    provider_id_data = {}
    provider_data = {}

    video_map = {}

    entries.each do |entry, hash|
      if id = entry.main_tweet_id
        provider_id_data[entry.id] = id
        provider_data[entry.id] = 0
      elsif id = entry.data.safe_dig("youtube_video_id")
        provider_id_data[entry.id] = id
        provider_data[entry.id] = 1
        video_map[entry.id] = id
      end
    end

    if video_map.present?
      channel_map = Embed.youtube_video.where(provider_id: video_map.values).pluck(:provider_id, :parent_id).to_h
      video_map.each do |entry_id, video_id|
        if channel_id = channel_map[video_id]
          provider_parent_id_data[entry_id] = channel_id
        end
      end
    end

    if provider_id_data.present?
      Entry.update_multiple(column: :provider_id, data: provider_id_data)
      Entry.update_multiple(column: :provider, data: provider_data)
    end
    if provider_parent_id_data.present?
      Entry.update_multiple(column: :provider_parent_id, data: provider_parent_id_data)
    end
  end

  def build
    jobs = job_args(Entry.last.id)
    Sidekiq::Client.push_bulk(
      "args" => jobs,
      "class" => self.class
    )
  end
end
