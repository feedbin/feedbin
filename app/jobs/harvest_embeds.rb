class HarvestEmbeds
  include Sidekiq::Worker
  
  def perform(entry_id)
    entry = Entry.find(entry_id)
    items = []
    
    want_video_ids = Nokogiri::HTML5(entry.content).css("iframe").each_with_object([]) do |iframe, array|
      if match = IframeEmbed::Youtube.recognize_url?(iframe["src"])
        array.push(match[1])
      end
    end
    
    video_id = entry.data&.dig("youtube_video_id")
    want_video_ids.push(video_id) if video_id
    
    have_video_ids = Embed.youtube_video.where(provider_id: want_video_ids).pluck(:provider_id)
    want_video_ids = want_video_ids - have_video_ids
    
    return if want_video_ids.empty?
    
    videos = youtube_api(type: "videos", ids: want_video_ids, parts: ["snippet", "contentDetails"])
    
    want_channel_ids = videos.dig("items")&.each_with_object([]) do |video, array| 
      channel_id = video.dig("snippet", "channelId")
      array.push(channel_id) if channel_id
    end

    have_channel_ids = Embed.youtube_channel.where(provider_id: want_channel_ids).pluck(:provider_id)
    want_channel_ids = want_channel_ids - have_channel_ids
    if want_channel_ids.present?
      channels = youtube_api(type: "channels", ids: want_channel_ids, parts: ["snippet"])
      items = channels.dig("items")&.each_with_object(items) do |item, array| 
        item = Embed.new(data: item, provider_id: item.dig("id"), source: :youtube_channel)
        array.push(item)
      end
      update_feed_icons(channels)
    end    

    items = videos.dig("items")&.each_with_object(items) do |item, array| 
      item = Embed.new(data: item, provider_id: item.dig("id"), parent_id: item.dig("snippet", "channelId"), source: :youtube_video)
      array.push(item)
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