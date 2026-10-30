module Api
  module V3
    # The feed object. Load feeds with Feed::ICON_PRELOADS and
    # :touch_icon_image_record so the image rows come preloaded.
    class FeedSerializer
      def initialize(feed, posts_per_week:)
        @feed = feed
        @posts_per_week = posts_per_week
      end

      def to_h
        {
          object: "feed",
          id: @feed.id,
          title: @feed.title.presence,
          description: @feed.feed_description&.to_plain_text.presence,
          kind: kind,
          feed_url: @feed.feed_url,
          site_url: @feed.site_url.presence,
          hostname: @feed.host || hostname(@feed.site_url) || hostname(@feed.feed_url),
          images: {
            favicon: image(@feed.favicon_image_record),
            touch_icon: image(@feed.touch_icon_image_record),
            icon: image(@feed.icon_image_record || @feed.channel_image_record)
          },
          health: health,
          stats: {
            subscriber_count: @feed.subscriptions_count,
            posts_per_week: @posts_per_week
          },
          channel_id: @feed.channel_id,
          # Feedbin doesn't store the List-Unsubscribe header yet.
          list_unsubscribe: nil
        }
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

      def hostname(url)
        url.presence && Addressable::URI.parse(url).host
      rescue Addressable::URI::InvalidURIError
        nil
      end
    end
  end
end
