module Api
  module V3
    class VideoLoader
      IFRAME_SRC = /<iframe\b[^>]*?\ssrc\s*=\s*(["'])(.*?)\1/im

      # A regex scan, not a parse: this runs over every entry of every response.
      def self.video_ids(html)
        return [] if html.blank?
        html.scan(IFRAME_SRC).filter_map do |_, src|
          match = IframeEmbed::Youtube.recognize_url?(CGI.unescapeHTML(src))
          match && match[1].presence
        end.uniq
      end

      # {entry id => [video object]}. Videos with no Embed row are left out.
      def self.call(entries)
        ids = entries.to_h { [it.id, video_ids(it.rendering.api)] }
        wanted = ids.values.flatten.uniq
        return ids.transform_values { [] } if wanted.empty?

        videos = Embed.youtube_video.where(provider_id: wanted).index_by(&:provider_id)
        channel_ids = videos.values.filter_map(&:parent_id).uniq
        channels = channel_ids.any? ? Embed.youtube_channel.where(provider_id: channel_ids).index_by(&:provider_id) : {}
        images = channels.any? ? Image.provider_embed_icon.where(provider_id: channels.keys).group_by(&:provider_id).transform_values(&:first) : {}

        serialized = videos.transform_values do |video|
          VideoSerializer.new(video, channel: channels[video.parent_id], channel_image: images[video.parent_id]).to_h
        end
        ids.transform_values { it.filter_map { serialized[_1] } }
      end
    end
  end
end
