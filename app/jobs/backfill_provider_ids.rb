class BackfillProviderIds
  include Sidekiq::Worker
  include SidekiqHelper
  sidekiq_options queue: :utility

  def perform(batch)
    ids = build_ids(batch)
    entries = Entry.where(id: ids).select(:id, :feed_id, :url, :data, :image).includes(:feed)

    provider_parent_id_data = {}
    provider_id_data = {}
    provider_data = {}
    image_provider_id_data = {}
    image_provider_data = {}

    video_map = {}

    entries.each do |entry|
      if entry.tweet? && entry.tweet.main_tweet.user.screen_name
        provider_data[entry.id]           = Entry.providers[:twitter]
        provider_id_data[entry.id]        = entry.tweet.main_tweet.id
        image_provider_id_data[entry.id]  = entry.tweet.main_tweet.user.screen_name
        image_provider_data[entry.id]     = Image.providers[:entry_icon]
      elsif id = entry.data.safe_dig("youtube_video_id")
        provider_data[entry.id]    = Entry.providers[:youtube]
        provider_id_data[entry.id] = id
        video_map[entry.id]        = id
      elsif entry.feed.pages?
        image_provider_data[entry.id]    = Image.providers[:entry_icon]
        image_provider_id_data[entry.id] = entry.hostname
      end
    end

    if video_map.present?
      channel_map = Embed.youtube_video.where(provider_id: video_map.values).pluck(:provider_id, :parent_id).to_h
      video_map.each do |entry_id, video_id|
        if channel_id = channel_map[video_id]
          provider_parent_id_data[entry_id] = channel_id
          image_provider_id_data[entry_id]  = channel_id
          image_provider_data[entry.id]     = Image.providers[:entry_icon]
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

    if image_provider_id_data.present?
      Entry.update_multiple(column: :image_provider_id, data: image_provider_id_data)
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
