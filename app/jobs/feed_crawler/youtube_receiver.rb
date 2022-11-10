module FeedCrawler
  class YoutubeReceiver
    include Sidekiq::Worker
    sidekiq_options queue: :parse

    def perform(data)
      ids = data["entries"].map { |entry| entry.dig("data", "youtube_video_id") }
      embeds = Embed.youtube_video.where(provider_id: ids).index_by(&:provider_id)

      data["entries"].map do |entry|
        id = entry.dig("data", "youtube_video_id")
        if embed = embeds[id]
          content = embed.data.dig("snippet", "description")
          if content.present? && entry.dig("content").blank?
            entry["content"] = content
            unless embed.duration_in_seconds == 0
              entry["embed_duration"] = embed.duration_in_seconds
            end
          end
        end
      end

      Receiver.new.perform(data)
    end

  end
end