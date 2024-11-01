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
      download_data(ids)
    end
  end

  def download_data(ids)
    items = []

    videos = youtube_api(type: "videos", ids: ids, parts: ["snippet", "contentDetails"])
    items.concat(videos.safe_dig("items")&.map { |item, array|
      Embed.new(data: item, provider_id: item.safe_dig("id"), parent_id: item.safe_dig("snippet", "channelId"), source: :youtube_video)
    })

    channel_ids = videos.safe_dig("items")&.map { |video| video.safe_dig("snippet", "channelId") }.uniq
    channels = youtube_api(type: "channels", ids: channel_ids, parts: ["snippet"])
    items.concat(channels.safe_dig("items")&.map { |item|
      Embed.new(data: item, provider_id: item.safe_dig("id"), source: :youtube_channel)
    })

    Embed.import(items, on_duplicate_key_update: {conflict_target: [:source, :provider_id], columns: [:data]}) if items.present?

    update_feed_icons(ids)
  end

  def update_feed_icons(ids)
    channel_ids = Embed.youtube_video.where(provider_id: ids).pluck(:parent_id)
    channels = Embed.youtube_channel.where(provider_id: channel_ids).distinct
    channels.each do |channel|
      if feed = Feed.find_by_feed_url("https://www.youtube.com/feeds/videos.xml?channel_id=#{channel.provider_id}")
        feed.update(custom_icon: channel.data.safe_dig("snippet", "thumbnails", "default", "url"))
      end
    end
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
end
