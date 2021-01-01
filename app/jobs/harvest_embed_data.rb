class HarvestEmbedData
  include Sidekiq::Worker

  def perform
    temporary_set = "#{self.class.name}-#{jid}"

    (_, _, videos) = Sidekiq.redis do |redis|
      redis.pipelined do
        redis.renamenx(HarvestEmbeds::SET_NAME, temporary_set)
        redis.expire(temporary_set, 60)
        redis.smembers(temporary_set)
      end
    end

    videos.each_slice(50) do |ids|
      download_data(ids)
    end
  rescue Redis::CommandError => exception
    return logger.info("Nothing to do") if exception.message =~ /no such key/i
    raise
  end

  def download_data(ids)
    items = []

    videos = youtube_api(type: "videos", ids: ids, parts: ["snippet", "contentDetails"])

    want = videos.dig("items")&.map { |video| video.dig("snippet", "channelId") }
    have = Embed.youtube_channel.where(provider_id: want).pluck(:provider_id)
    want = (want - have).uniq

    items.concat(videos.dig("items")&.map { |item, array|
      Embed.new(data: item, provider_id: item.dig("id"), parent_id: item.dig("snippet", "channelId"), source: :youtube_video)
    })

    if want.present?
      channels = youtube_api(type: "channels", ids: want, parts: ["snippet"])
      items.concat(channels.dig("items")&.map { |item|
        Embed.new(data: item, provider_id: item.dig("id"), source: :youtube_channel)
      })
      update_feed_icons(channels)
    end

    Embed.import(items, on_duplicate_key_update: {conflict_target: [:source, :provider_id], columns: [:data]}) if items.present?
  end

  def update_feed_icons(channels)
    channels.dig("items")&.each do |item, array|
      if feed = Feed.find_by_feed_url("https://www.youtube.com/feeds/videos.xml?channel_id=#{item.dig("id")}")
        options = feed.options
        options["icon"] = item.dig("snippet", "thumbnails", "default", "url")
        feed.update(options: options)
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