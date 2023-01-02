module FeedCrawler
  class UpdateYoutubeVideos
    include Sidekiq::Worker

    def perform(feed_id)
      feed = Feed.find(feed_id)
      entries = feed.entries
      ids = entries.filter_map { |entry| entry.data&.safe_dig("youtube_video_id") }
      embeds = Embed.youtube_video.where(provider_id: ids).index_by(&:provider_id)
      entries.map do |entry|
        id = entry.data&.safe_dig("youtube_video_id")
        if embed = embeds[id]
          unless embed.duration_in_seconds == 0
            entry.update(embed_duration: embed.duration_in_seconds)
          end
        end
      end
    end
  end
end