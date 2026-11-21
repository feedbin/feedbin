# Keeps YouTube's data for the videos entries show. An entry's videos are
# queued as it is saved; a run every minute sends the queue to YouTube in
# batches (HarvestEmbeds::Download).
class HarvestEmbeds
  include Sidekiq::Worker

  sidekiq_options retry: false

  SET_NAME = "#{name}-ids"
  # Ids sent to YouTube per run, every minute, so a backlog drains in steps
  # rather than in one burst.
  IDS_PER_RUN = 500
  # The most ids YouTube takes in one request.
  IDS_PER_REQUEST = 50
  # The embed patterns capture whatever sits where an id belongs. YouTube
  # refuses a request for one that isn't an id, and a refused batch is queued
  # again, so anything else would fail its batch on every pass.
  VIDEO_ID = /\A[\w-]+\z/

  # Both answer whether there was anything to queue.
  def self.enqueue(video_ids)
    return false if video_ids.empty?
    Sidekiq.redis { it.call("SADD", SET_NAME, video_ids) }
    true
  end

  # Queues the ids that have no stored video yet.
  def self.enqueue_missing(video_ids)
    video_ids = video_ids.uniq.grep(VIDEO_ID)
    enqueue(video_ids - Embed.youtube_video.where(provider_id: video_ids).pluck(:provider_id))
  end

  # Sends the queue to YouTube now rather than on the next minute's run, for
  # videos someone is about to look at.
  def self.harvest_now(video_ids)
    perform_async(nil, true) if enqueue_missing(video_ids)
  end

  def perform(entry_id, process = false)
    scan(Entry.find(entry_id)) if entry_id
    download_queued if process
  end

  private

  # Every video is queued; only the ones the entry shows are recorded for it.
  def scan(entry)
    document = Nokogiri::HTML5(entry.content)
    shown = [*youtube_ids(document.css("iframe"), "src"), entry.data&.safe_dig("youtube_video_id")].compact.uniq
    linked = youtube_ids(document.css("a"), "href")
    record_videos(entry, shown)
    self.class.enqueue_missing(shown + linked)
  end

  def youtube_ids(elements, attribute)
    elements.filter_map do |element|
      match = IframeEmbed::Youtube.recognize_url?(element[attribute])
      match[1] if match
    end
  end

  # A video can be stored before its EntryVideo row; the entry is marked edited then.
  def record_videos(entry, video_ids)
    added = EntryVideo.record(entry_id: entry.id, provider_ids: video_ids)
    return if added.empty?
    if Embed.youtube_video.where(provider_id: added).where("updated_at > ?", entry.created_at).exists?
      EntryVideo.bump(Entry.where(id: entry.id))
    end
  end

  def download_queued
    return if YoutubeApi.paused?
    video_ids = Sidekiq.redis { it.call("SPOP", SET_NAME, IDS_PER_RUN) }
    video_ids.each_slice(IDS_PER_REQUEST) { Download.perform_async(it) }
  end
end
