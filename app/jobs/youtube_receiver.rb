class YoutubeReceiver
  include Sidekiq::Worker
  sidekiq_options queue: :feed_refresher_receiver

  def perform(data)
    ids = data["entries"].map { |entry| entry.dig("data", "youtube_video_id") }
    embeds = Embed.youtube_video.where(provider_id: ids).index_by(&:provider_id)

    data["entries"].map do |entry|
      id = entry.dig("data", "youtube_video_id")
      if embed = embeds[id]
        content = embed.data.dig("snippet", "description")
        if content.present? && entry.dig("content").blank?
          entry["content"] = content
        end
      end
    end

    FeedRefresherReceiver.new.perform(data)
  end

end