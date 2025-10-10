class HarvestEmbeds
  include Sidekiq::Worker
  include SidekiqHelper
  sidekiq_options retry: false
  SET_NAME = "#{name}-ids"

  def perform(entry_id, process = false)
    if entry_id
      find_embeds(entry_id)
    end

    if process
      cache_embeds
    end
  end

  def find_embeds(entry_id)
    entry = Entry.find(entry_id)

    want = Nokogiri::HTML5(entry.content).css("iframe, a").each_with_object([]) do |element, array|
      url = element["src"] || element["href"]
      if match = IframeEmbed::Youtube.recognize_url?(url)
        array.push(match[1])
      end
    end

    video_id = entry.data&.safe_dig("youtube_video_id")
    want.push(video_id) if video_id

    add_missing_to_queue(want)
  end

  def add_missing_to_queue(want)
    have = Embed.youtube_video.where(provider_id: want).pluck(:provider_id)
    want = (want - have).uniq
    add_to_queue(SET_NAME, want) if want.present?
  end

  def cache_embeds
    entry_ids = dequeue_ids(SET_NAME)
    entry_ids&.each_slice(50) do |ids|
      Download.perform_async(ids)
    end
  end

  class Download
    include Sidekiq::Worker

    def perform(ids)
      items = []

      videos      = youtube_api(type: "videos", ids: ids, parts: ["snippet", "contentDetails", "liveStreamingDetails"])
      channel_ids = videos.safe_dig("items")&.map { |video| video.safe_dig("snippet", "channelId") }.uniq
      channels    = youtube_api(type: "channels", ids: channel_ids, parts: ["snippet", "statistics", "brandingSettings"])

      video_embeds = videos.safe_dig("items")&.map do
        Embed.new(
          data: it,
          provider_id: it.safe_dig("id"),
          parent_id: it.safe_dig("snippet", "channelId"),
          source: :youtube_video
        )
      end

      channel_embeds = channels.safe_dig("items")&.map do
        Embed.new(
          data: it,
          provider_id: it.safe_dig("id"),
          source: :youtube_channel
        )
      end

      items.concat(video_embeds)

      items.concat(channel_embeds)

      if items.present?
        Embed.import(items, on_duplicate_key_update: {conflict_target: [:source, :provider_id], columns: [:data]})
      end

      update_related_records(ids)
    end

    def update_related_records(ids)
      videos    = Embed.youtube_video.where(provider_id: ids).includes(:parent)
      channels  = videos.map(&:parent).uniq
      video_map = videos.index_by(&:provider_id)

      channels.each do |channel|
        if feed = Feed.find_by_feed_url("https://www.youtube.com/feeds/videos.xml?channel_id=#{channel.provider_id}")
          feed.update(custom_icon: channel.data.safe_dig("snippet", "thumbnails", "default", "url"))
        end
      end

      Entry.provider_youtube.where(provider_id: ids).each do |entry|
        if embed = video_map[entry.provider_id]
          entry.update(provider_parent_id: embed.parent_id, embed_duration: embed.duration_in_seconds)
        end
      end

      requeue_live_videos(videos)
    end

    def requeue_live_videos(videos)
      videos.each do |video|
        if redownload?(video)
          delay = if video.scheduled_time > Time.now
            video.scheduled_time + 1.hour - Time.now
          else
            1.hour
          end
          Sidekiq.logger.info "HarvestEmbeds redownload id=#{video.provider_id} delay=#{delay}"
          Redownload.perform_in(delay, video.provider_id)
        end
      end
    end

    def redownload?(video)
      return false if video.live_broadcast_content == "none"
      return false if !video.scheduled_time
      return false if video.scheduled_time < 24.hours.ago
      true
    end

    def youtube_api(type:, ids:, parts:)
      options = {
        params: {
          key: ENV["YOUTUBE_KEY"],
          part: parts.join(","),
          id: ids.join(",")
        }
      }
      response = UrlCache.new("https://www.googleapis.com/youtube/v3/#{type}", options).body
      JSON.parse(response)
    end


    class Redownload
      include Sidekiq::Worker
      include SidekiqHelper

      def perform(id)
        add_to_queue(SET_NAME, [*id])
      end
    end
  end
end
