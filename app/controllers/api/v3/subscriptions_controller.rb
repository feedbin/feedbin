module Api
  module V3
    # GET /subscriptions: every subscription, with its feed and tags
    # embedded, in one response with an ETag.
    class SubscriptionsController < ApiController
      def index
        return if not_modified?(list_etag("subscriptions"))

        subscriptions = @user.subscriptions
          .includes(feed: [*Feed::ICON_PRELOADS, :touch_icon_image_record])
          .order(:id)
          .to_a
        feeds = subscriptions.map(&:feed).uniq(&:id).to_h { [_1.id, FeedSerializer.new(_1).to_h] }
        tags = tags_by_feed_id

        render_list(subscriptions.map { SubscriptionSerializer.new(_1, feed: feeds[_1.feed_id], tags: tags.fetch(_1.feed_id, [])).to_h })
      end

      private

      # {feed_id => [[tag_id, name], ...]}, names in natural order.
      def tags_by_feed_id
        @user.taggings.joins(:tag).pluck(:feed_id, :tag_id, "tags.name")
          .group_by(&:first)
          .transform_values { |rows| rows.map { _1.drop(1) }.sort_by { _1.last.downcase } }
      end
    end
  end
end
