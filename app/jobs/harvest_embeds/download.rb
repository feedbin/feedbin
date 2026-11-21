class HarvestEmbeds
  # Fetches a batch of videos and their channels, stores what changed, then
  # brings whatever shows them up to date.
  class Download
    include Sidekiq::Worker

    # A channel is fetched at most once a day: it changes rarely, and the
    # request would otherwise spend a second unit on every batch.
    CHANNEL_FRESH_FOR = 1.day

    def perform(video_ids)
      video_ids = video_ids.grep(VIDEO_ID)
      return if video_ids.empty?

      videos = YoutubeApi.videos(video_ids)
      # Nothing else queues these ids again.
      return HarvestEmbeds.enqueue(video_ids) unless videos

      # The channels request can fail on its own; the videos are stored anyway.
      channels = YoutubeApi.channels(stale_channel_ids(videos)) || []
      changed = Embed.store_youtube(videos:, channels:)
      mark_fresh(channels)

      update_related_records(video_ids, changed)
    end

    private

    def stale_channel_ids(videos)
      ids = videos.filter_map { it.safe_dig("snippet", "channelId") }.uniq
      return [] if ids.empty?
      keys = ids.map { channel_key(it) }
      fresh = Sidekiq.redis { it.call("MGET", *keys) }
      ids.zip(fresh).filter_map { |id, stored| id unless stored }
    end

    def mark_fresh(channels)
      return if channels.empty?
      Sidekiq.redis do |redis|
        redis.pipelined do |pipeline|
          channels.each { pipeline.call("SET", channel_key(it["id"]), "1", "EX", CHANNEL_FRESH_FOR.to_i) }
        end
      end
    end

    def channel_key(id)
      "HarvestEmbeds-channel-fresh:#{id}"
    end

    # changed: the provider ids, videos and channels, whose data was just stored.
    def update_related_records(video_ids, changed)
      videos = Embed.youtube_video.where(provider_id: video_ids).includes(parent: :channel_image)
      crawl_channel_images(videos, changed)
      update_entries(videos)
      EntryVideo.bump_for_videos(videos.map(&:provider_id) & changed)
      requeue_unfinished_streams(videos)
    end

    # A video has no parent when its channel was never stored.
    def crawl_channel_images(videos, changed)
      videos.filter_map(&:parent).uniq.each do |channel|
        next if channel.channel_image && !changed.include?(channel.provider_id)
        ImageCrawler::ChannelImage.schedule(channel)
      end
    end

    # Saved only on a change: a save re-renders, re-indexes and harvests again.
    def update_entries(videos)
      by_id = videos.index_by(&:provider_id)
      Entry.provider_youtube.where(provider_id: by_id.keys).each do |entry|
        video = by_id[entry.provider_id]
        entry.assign_attributes(provider_parent_id: video.parent_id, embed_duration: video.duration_in_seconds)
        entry.save if entry.changed?
      end
    end

    # Looked at again an hour after the stream starts, then hourly.
    def requeue_unfinished_streams(videos)
      videos.select(&:unfinished_stream?).each do |video|
        delay = [video.start_time - Time.now, 0].max + 1.hour
        Sidekiq.logger.info "HarvestEmbeds redownload id=#{video.provider_id} delay=#{delay}"
        Redownload.perform_in(delay, video.provider_id)
      end
    end

    class Redownload
      include Sidekiq::Worker

      def perform(id)
        HarvestEmbeds.enqueue([*id])
      end
    end
  end
end
