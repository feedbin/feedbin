module Api
  module V3
    # Preload Feed::ICON_PRELOADS and :touch_icon_image_record to avoid N+1s.
    # candidate: {subscription_id:, daily_entry_counts:} from Find feeds.
    class FeedSerializer
      def initialize(feed, candidate: nil)
        @feed = feed
        @candidate = candidate
      end

      def to_h
        hash = {
          object: "feed",
          id: @feed.id,
          title: @feed.title.presence,
          description: @feed.feed_description&.to_plain_text.presence,
          kind: kind,
          feed_url: @feed.feed_url,
          site_url: @feed.site_url.presence,
          hostname: @feed.hostname,
          images: {
            favicon: image(@feed.favicon_image_record),
            touch_icon: image(@feed.touch_icon_image_record),
            icon: image(@feed.icon_image_record || @feed.channel_image_record)
          },
          health: health,
          channel_id: @feed.channel_id
        }
        hash.merge!(@candidate) if @candidate
        hash
      end

      private

      def kind
        @feed.newsletter? ? "newsletter" : @feed.pages? ? "pages" : "xml"
      end

      def health
        status = if !@feed.crawl_error?
          "ok"
        elsif @feed.dead?
          "dead"
        else
          "erroring"
        end
        {
          status: status,
          last_published_at: @feed.last_published_entry&.utc&.iso8601,
          message: status == "ok" ? nil : @feed.crawl_error_message
        }
      end

      def image(record)
        record && ImageSerializer.new(record).to_h
      end
    end
  end
end
