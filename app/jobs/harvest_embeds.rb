class HarvestEmbeds
  include Sidekiq::Worker
  include SidekiqHelper

  sidekiq_options retry: false

  SET_NAME = "#{name}-ids"
  PAUSE_KEY = "#{name}-paused"

  def perform(entry_id, process = false)
    find_embeds(entry_id) if entry_id
    cache_embeds if process
  end

  def find_embeds(entry_id)
    entry = Entry.find(entry_id)
    iframed, linked = youtube_ids(entry)
    record_videos(entry, iframed)
    add_missing_to_queue(iframed + linked)
  end

  def add_missing_to_queue(video_ids)
    missing = video_ids.uniq - Embed.youtube_video.where(provider_id: video_ids).pluck(:provider_id)
    add_to_queue(SET_NAME, missing) if missing.present?
  end

  def self.paused?
    Sidekiq.redis { it.call("EXISTS", PAUSE_KEY) } == 1
  end

  # YouTube's daily quota resets at midnight Pacific.
  def self.pause_until_quota_resets
    now = Time.now.in_time_zone("America/Los_Angeles")
    seconds = (now.tomorrow.beginning_of_day - now).ceil
    Sidekiq.redis { it.call("SET", PAUSE_KEY, "1", "EX", seconds) }
  end

  private

  # => [iframed ids, linked ids]
  def youtube_ids(entry)
    iframed = []
    linked = []
    Nokogiri::HTML5(entry.content).css("iframe, a").each do |element|
      match = IframeEmbed::Youtube.recognize_url?(element["src"] || element["href"])
      ((element.name == "iframe") ? iframed : linked).push(match[1]) if match
    end
    iframed.push(entry.data&.safe_dig("youtube_video_id"))
    [iframed.compact.uniq, linked]
  end

  # The feed crawler queues video ids before the entry exists, so a video
  # can be stored before its EntryVideo row; the entry is marked edited then.
  def record_videos(entry, video_ids)
    added = EntryVideo.record(entry_id: entry.id, provider_ids: video_ids)
    return if added.empty?
    if Embed.youtube_video.where(provider_id: added).where("updated_at > ?", entry.created_at).exists?
      EntryVideo.bump(Entry.where(id: entry.id))
    end
  end

  def cache_embeds
    return if self.class.paused?
    dequeue_ids(SET_NAME)&.each_slice(50) { |video_ids| Download.perform_async(video_ids) }
  end

  class Download
    include Sidekiq::Worker
    include SidekiqHelper

    def perform(video_ids)
      videos = youtube_api("videos", video_ids, %w[snippet contentDetails liveStreamingDetails])
      # Nothing else queues these ids again.
      return add_to_queue(SET_NAME, video_ids) unless videos

      # Deleted, private and region-blocked videos come back with no "items".
      video_items = videos["items"] || []
      channel_ids = video_items.map { it.safe_dig("snippet", "channelId") }.uniq
      channel_items = youtube_api("channels", channel_ids, %w[snippet statistics brandingSettings])&.dig("items") || []

      embeds = video_items.map { embed(it, :youtube_video, parent_id: it.safe_dig("snippet", "channelId")) } +
        channel_items.map { embed(it, :youtube_channel) }
      changed = changed_embeds(embeds)
      Embed.import(changed, on_duplicate_key_update: {conflict_target: [:source, :provider_id], columns: [:data]}) if changed.present?

      update_related_records(video_ids, changed.map(&:provider_id))
    end

    private

    def embed(item, source, parent_id: nil)
      Embed.new(data: item, provider_id: item["id"], parent_id: parent_id, source: source)
    end

    # A live stream is fetched hourly; an unchanged answer must not touch
    # its entries or channel.
    def changed_embeds(embeds)
      return [] if embeds.empty?
      stored = Embed.where(provider_id: embeds.map(&:provider_id).uniq)
        .pluck(:source, :provider_id, :data)
        .to_h { |source, provider_id, data| [[source, provider_id], data] }
      embeds.reject { stored[[it.source, it.provider_id]] == it.data }
    end

    def update_related_records(video_ids, changed)
      videos = Embed.youtube_video.where(provider_id: video_ids).includes(parent: :channel_image)
      crawl_channel_images(videos, changed)
      update_entries(videos)
      EntryVideo.bump_for_videos(videos.map(&:provider_id) & changed)
      requeue_live_videos(videos)
    end

    # The channels request can fail while the videos one succeeded, so a
    # video may have no parent.
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

    def requeue_live_videos(videos)
      videos.select { redownload?(it) }.each do |video|
        delay = [video.start_time - Time.now, 0].max + 1.hour
        Sidekiq.logger.info "HarvestEmbeds redownload id=#{video.provider_id} delay=#{delay}"
        Redownload.perform_in(delay, video.provider_id)
      end
    end

    # Until the stream ends, for up to a day after it started or was due to.
    def redownload?(video)
      video.live_broadcast_content != "none" &&
        video.actual_end_time.nil? &&
        video.start_time.present? &&
        video.start_time >= 24.hours.ago
    end

    # Not through UrlCache: a redownload has to see the stream's current state.
    def youtube_api(type, ids, parts)
      response = HTTP.timeout(write: 5, connect: 5, read: 10)
        .get("https://www.googleapis.com/youtube/v3/#{type}", params: {key: ENV["YOUTUBE_KEY"], part: parts.join(","), id: ids.join(",")})
      return JSON.parse(response.to_s) if response.status.success?

      Sidekiq.logger.info "HarvestEmbeds youtube_api failed type=#{type} status=#{response.status.code}"
      HarvestEmbeds.pause_until_quota_resets if response.status.code == 403 && response.to_s.include?("quotaExceeded")
      nil
    rescue HTTP::Error, OpenSSL::SSL::SSLError
      nil
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
