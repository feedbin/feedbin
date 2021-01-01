class HarvestEmbeds
  include Sidekiq::Worker
  sidekiq_options retry: false
  SET_NAME = "#{name}-ids"

  def perform(entry_id)
    entry = Entry.find(entry_id)

    want = Nokogiri::HTML5(entry.content).css("iframe").each_with_object([]) do |iframe, array|
      if match = IframeEmbed::Youtube.recognize_url?(iframe["src"])
        array.push(match[1])
      end
    end

    video_id = entry.data&.dig("youtube_video_id")
    want.push(video_id) if video_id

    have = Embed.youtube_video.where(provider_id: want).pluck(:provider_id)
    want = (want - have).uniq

    Sidekiq.redis { |redis| redis.sadd(SET_NAME, want) } if want.present?
  end
end