class HarvestEmbeds
  include Sidekiq::Worker
  include SidekiqHelper

  sidekiq_options retry: false

  SET_NAME = "#{name}-ids"
  PAUSE_KEY = "#{name}-paused"
  # How many pauses in a row, each twice the last; a successful request clears it.
  BACKOFF_KEY = "#{name}-backoff"
  FIRST_PAUSE = 5.minutes
  LONGEST_PAUSE = 1.hour
  # Ids sent to YouTube per run, every minute, so a backlog drains in steps
  # rather than in one burst.
  IDS_PER_RUN = 500
  # The embed patterns capture whatever sits where an id belongs. YouTube
  # refuses a request for one that isn't an id, and a refused batch is queued
  # again, so anything else would fail its batch on every pass.
  VIDEO_ID = /\A[\w-]+\z/

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
    video_ids = video_ids.uniq.grep(VIDEO_ID)
    missing = video_ids - Embed.youtube_video.where(provider_id: video_ids).pluck(:provider_id)
    add_to_queue(SET_NAME, missing) if missing.present?
  end

  def self.paused?
    Sidekiq.redis { it.call("EXISTS", PAUSE_KEY) } == 1
  end

  # Nothing assumed about YouTube's limits or when they reset: a refused
  # request costs no quota, so asking again later is free. The batches already
  # sent are refused together; only the first refusal lengthens the pause.
  def self.back_off
    Sidekiq.redis do |redis|
      next unless redis.call("SET", PAUSE_KEY, "1", "NX", "EX", LONGEST_PAUSE.to_i)
      step = redis.call("INCR", BACKOFF_KEY)
      redis.call("EXPIRE", BACKOFF_KEY, 1.day.to_i)
      redis.call("EXPIRE", PAUSE_KEY, [FIRST_PAUSE * 2**(step - 1), LONGEST_PAUSE].min.to_i)
    end
  end

  def self.reset_backoff
    Sidekiq.redis { it.call("DEL", BACKOFF_KEY) }
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

  # A video can be stored before its EntryVideo row; the entry is marked edited then.
  def record_videos(entry, video_ids)
    added = EntryVideo.record(entry_id: entry.id, provider_ids: video_ids)
    return if added.empty?
    if Embed.youtube_video.where(provider_id: added).where("updated_at > ?", entry.created_at).exists?
      EntryVideo.bump(Entry.where(id: entry.id))
    end
  end

  def cache_embeds
    return if self.class.paused?
    video_ids = Sidekiq.redis { it.call("SPOP", SET_NAME, IDS_PER_RUN) }
    video_ids.each_slice(50) { Download.perform_async(it) }
  end

  class Download
    include Sidekiq::Worker
    include SidekiqHelper

    def perform(video_ids)
      video_ids = video_ids.grep(VIDEO_ID)
      return if video_ids.empty?

      videos = youtube_api("videos", video_ids, %w[snippet contentDetails liveStreamingDetails])
      # Nothing else queues these ids again.
      return add_to_queue(SET_NAME, video_ids) unless videos

      # Deleted, private and region-blocked videos come back with no "items".
      video_items = videos["items"] || []
      channel_ids = stale_channels(video_items.filter_map { it.safe_dig("snippet", "channelId") }.uniq)
      channel_items = channel_ids.empty? ? [] : youtube_api("channels", channel_ids, %w[snippet statistics brandingSettings])&.dig("items") || []

      embeds = video_items.map { embed(it, :youtube_video, parent_id: it.safe_dig("snippet", "channelId")) } +
        channel_items.map { embed(it, :youtube_channel) }
      changed = changed_embeds(embeds)
      Embed.import(changed, on_duplicate_key_update: {conflict_target: [:source, :provider_id], columns: [:data]}) if changed.present?
      mark_fresh(channel_items.map { it["id"] })

      update_related_records(video_ids, changed.map(&:provider_id))
    end

    private

    # A channel is fetched at most once a day: it changes rarely, and the
    # request would otherwise spend a second unit on every batch.
    CHANNEL_FRESH_FOR = 1.day

    def stale_channels(ids)
      return [] if ids.empty?
      keys = ids.map { channel_key(it) }
      fresh = Sidekiq.redis { it.call("MGET", *keys) }
      ids.zip(fresh).filter_map { |id, stored| id unless stored }
    end

    def mark_fresh(ids)
      return if ids.empty?
      Sidekiq.redis do |redis|
        redis.pipelined { |pipeline| ids.each { pipeline.call("SET", channel_key(it), "1", "EX", CHANNEL_FRESH_FOR.to_i) } }
      end
    end

    def channel_key(id)
      "#{HarvestEmbeds.name}-channel-fresh:#{id}"
    end

    def embed(item, source, parent_id: nil)
      Embed.new(data: item, provider_id: item["id"], parent_id: parent_id, source: source)
    end

    # Live streams are refetched hourly; an unchanged answer must not touch anything.
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

    # The channels request can fail independently, so a video may have no parent.
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
      body = response.to_s
      if response.status.success?
        HarvestEmbeds.reset_backoff
        return without_nul(JSON.parse(body))
      end

      Sidekiq.logger.info "HarvestEmbeds youtube_api failed type=#{type} status=#{response.status.code} body=#{body[0, 500].squish}"
      HarvestEmbeds.back_off if refused?(response.status.code, body)
      nil
    rescue HTTP::Error, OpenSSL::SSL::SSLError
      nil
    end

    # YouTube answers 403 quotaExceeded or rateLimitExceeded (also
    # userRateLimitExceeded); Google's front end can answer 429.
    def refused?(status, body)
      status == 429 || (status == 403 && body.match?(/quotaExceeded|rateLimitExceeded/i))
    end

    # jsonb refuses \u0000, and one in a channel's description failed the
    # whole batch's import.
    def without_nul(value)
      case value
      when String then value.delete("\u0000")
      when Array then value.map { without_nul(it) }
      when Hash then value.to_h { [without_nul(_1), without_nul(_2)] }
      else value
      end
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
