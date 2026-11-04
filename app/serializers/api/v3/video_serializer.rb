module Api
  module V3
    # The video object: a YouTube video iframed in an entry, from its
    # harvested Embed row, for clients that draw their own player card.
    # channel is the video's youtube_channel Embed and channel_image that
    # channel's avatar Image; either may be missing.
    class VideoSerializer
      POSTER_SIZES = %w[maxres standard high medium default].freeze

      def initialize(video, channel: nil, channel_image: nil)
        @video = video
        @channel = channel
        @channel_image = channel_image
      end

      def to_h
        {
          object: "video",
          provider: "youtube",
          id: @video.provider_id,
          url: "https://youtu.be/#{@video.provider_id}",
          title: @video.data.safe_dig("snippet", "title"),
          duration_in_seconds: @video.duration_in_seconds,
          live: @video.live_broadcast_content || "none",
          scheduled_start_at: @video.scheduled_time&.utc&.iso8601,
          poster: poster,
          channel: channel,
          chapters: chapters
        }
      end

      private

      def poster
        thumbnails = @video.data.safe_dig("snippet", "thumbnails") || {}
        size = POSTER_SIZES.find { thumbnails.dig(it, "url").present? } or return nil
        thumbnail = thumbnails[size]
        {url: thumbnail["url"], width: thumbnail["width"], height: thumbnail["height"]}
      end

      def channel
        return nil unless @channel
        {
          id: @channel.provider_id,
          title: @channel.data.safe_dig("snippet", "title"),
          icon: @channel_image && ImageSerializer.new(@channel_image).to_h
        }
      end

      def chapters
        @video.chapters.map do
          {start_in_seconds: it[:seconds], title: it[:title], duration_in_seconds: it[:duration]}
        end
      end
    end
  end
end
