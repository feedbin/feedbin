module Api
  module V3
    # GET /feeds: the feeds the user subscribes to, in one response with an
    # ETag. Subscriptions carry what the user did; this list carries what the
    # crawler knows (title, health, images), so a client refreshes it on its
    # own cadence.
    class FeedsController < ApiController
      def index
        feed_ids = @user.subscriptions.select(:feed_id)
        return if not_modified?(feeds_etag(feed_ids))

        feeds = Feed.where(id: feed_ids).includes(*Feed::ICON_PRELOADS, :touch_icon_image_record).order(:id)
        render_list(feeds.map { FeedSerializer.new(_1).to_h })
      end

      private

      # The set of feeds changes with the subscriptions list, and a feed's row
      # changes whenever the crawler saves it, so the subscriptions version and
      # the newest updated_at together move on every change a client sees.
      def feeds_etag(feed_ids)
        newest = Feed.where(id: feed_ids).maximum(:updated_at)
        %("feeds:#{@user.id}:#{versions.fetch("subscriptions")}:#{newest ? (newest.to_r * 1_000_000).to_i : 0}")
      end
    end
  end
end
