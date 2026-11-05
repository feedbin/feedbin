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

    iframed = []
    linked = []
    Nokogiri::HTML5(entry.content).css("iframe, a").each do |element|
      url = element["src"] || element["href"]
      if match = IframeEmbed::Youtube.recognize_url?(url)
        (element.name == "iframe" ? iframed : linked).push(match[1])
      end
    end

    video_id = entry.data&.safe_dig("youtube_video_id")
    iframed.push(video_id) if video_id

    record_videos(entry, iframed.uniq)
    add_missing_to_queue(iframed + linked)
  end

  # The videos an entry shows as players (API v3 lists them), so their
  # harvest can mark the entry edited. A video stored after the entry was
  # created but before this row existed (the feed crawler queues ids ahead
  # of the entry) may have missed a client that already synced the entry,
  # so the entry is marked here. Only for newly recorded videos: entries
  # are scanned again on every update.
  def record_videos(entry, ids)
    added = EntryVideo.record(entry_id: entry.id, provider_ids: ids)
    return if added.empty?
    if Embed.youtube_video.where(provider_id: added).where("updated_at > ?", entry.created_at).exists?
      EntryVideo.bump(Entry.where(id: entry.id))
    end
  end

  def add_missing_to_queue(want)
    have = Embed.youtube_video.where(provider_id: want).pluck(:provider_id)
    want = (want - have).uniq
    add_to_queue(SET_NAME, want) if want.present?
  end

  def cache_embeds
    return if self.class.paused?
    entry_ids = dequeue_ids(SET_NAME)
    entry_ids&.each_slice(50) do |ids|
      Download.perform_async(ids)
    end
  end

  PAUSE_KEY = "#{name}-paused"

  def self.paused?
    Sidekiq.redis { it.call("EXISTS", PAUSE_KEY) } == 1
  end

  # YouTube's daily quota resets at midnight Pacific. Until then every request
  # fails, so the queue just collects ids.
  def self.pause_until_quota_resets
    now = Time.now.in_time_zone("America/Los_Angeles")
    seconds = (now.tomorrow.beginning_of_day - now).ceil
    Sidekiq.redis { it.call("SET", PAUSE_KEY, "1", "EX", seconds) }
  end

  class Download
    include Sidekiq::Worker
    include SidekiqHelper

    def perform(ids)
      videos = youtube_api(type: "videos", ids: ids, parts: ["snippet", "contentDetails", "liveStreamingDetails"])

      # Nothing else queues these ids again, and for a stream this is the
      # link in its re-check chain, so a failed batch goes back in the queue.
      unless videos
        add_to_queue(SET_NAME, ids)
        return
      end

      # No "items" key is the ordinary answer for deleted, private, or
      # region-blocked ids -- normalise to [].
      video_items = videos.safe_dig("items") || []
      channel_ids = video_items.map { |video| video.safe_dig("snippet", "channelId") }.uniq
      channels    = youtube_api(type: "channels", ids: channel_ids, parts: ["snippet", "statistics", "brandingSettings"])
      channel_items = channels&.safe_dig("items") || []

      video_embeds = video_items.map do
        Embed.new(
          data: it,
          provider_id: it.safe_dig("id"),
          parent_id: it.safe_dig("snippet", "channelId"),
          source: :youtube_video
        )
      end

      channel_embeds = channel_items.map do
        Embed.new(
          data: it,
          provider_id: it.safe_dig("id"),
          source: :youtube_channel
        )
      end

      changed = changed_embeds(video_embeds + channel_embeds)
      if changed.present?
        Embed.import(changed, on_duplicate_key_update: {conflict_target: [:source, :provider_id], columns: [:data]})
      end

      update_related_records(ids, changed: changed.map(&:provider_id))
    end

    # The embeds whose data differs from what is stored, new ones included.
    # A stream is fetched hourly while it is live; an unchanged answer must
    # not mark entries edited, re-render them, or re-crawl the avatar.
    def changed_embeds(embeds)
      return [] if embeds.empty?
      stored = Embed.where(provider_id: embeds.map(&:provider_id).uniq)
        .pluck(:source, :provider_id, :data)
        .to_h { |source, provider_id, data| [[source, provider_id], data] }
      embeds.reject { stored[[it.source, it.provider_id]] == it.data }
    end

    def update_related_records(ids, changed: ids)
      videos    = Embed.youtube_video.where(provider_id: ids).includes(parent: :channel_image)
      # filter_map: the channels half of the API can come back empty (quota,
      # terminated channels) while the videos half succeeded.
      channels  = videos.filter_map(&:parent).uniq
      video_map = videos.index_by(&:provider_id)

      channels.each do |channel|
        # Keyed by the channel, feed or no feed: a playlist entry from a
        # channel nobody subscribes to directly resolves through the same
        # row. Crawled again only when the channel changed or has no avatar.
        next if channel.channel_image && !changed.include?(channel.provider_id)
        ImageCrawler::ChannelImage.schedule(channel)
      end

      Entry.provider_youtube.where(provider_id: ids).each do |entry|
        if embed = video_map[entry.provider_id]
          # Saved only on a change: a save runs the update callbacks
          # (rendering, views, search, another harvest) even when nothing did.
          entry.assign_attributes(provider_parent_id: embed.parent_id, embed_duration: embed.duration_in_seconds)
          entry.save if entry.changed?
        end
      end

      # Entries synced before this data changed refetch it as an edit.
      EntryVideo.bump_for_videos(videos.map(&:provider_id) & changed)

      requeue_live_videos(videos)
    end

    def requeue_live_videos(videos)
      videos.each do |video|
        if redownload?(video)
          start = video.start_time
          delay = if start > Time.now
            start + 1.hour - Time.now
          else
            1.hour
          end
          Sidekiq.logger.info "HarvestEmbeds redownload id=#{video.provider_id} delay=#{delay}"
          Redownload.perform_in(delay, video.provider_id)
        end
      end
    end

    # Checked again until the stream ends, for up to a day after it was due
    # to start or, for a stream that went live unscheduled, after it started.
    def redownload?(video)
      return false if video.live_broadcast_content == "none"
      return false if video.actual_end_time
      return false if !video.start_time
      return false if video.start_time < 24.hours.ago
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
      # Not through UrlCache: a stream's redownload has to see its current
      # state, and a week-old answer for the same ids would keep it live.
      response = HTTP.timeout(write: 5, connect: 5, read: 10)
        .get("https://www.googleapis.com/youtube/v3/#{type}", **options)
      return JSON.parse(response.to_s) if response.status.success?

      Sidekiq.logger.info "HarvestEmbeds youtube_api failed type=#{type} status=#{response.status.code}"
      if response.status.code == 403 && response.to_s.include?("quotaExceeded")
        HarvestEmbeds.pause_until_quota_resets
      end
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
