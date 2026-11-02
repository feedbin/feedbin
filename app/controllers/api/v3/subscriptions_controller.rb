module Api
  module V3
    # GET /subscriptions: every subscription in one response with an ETag.
    # Ids by default; expand=feed,tags embeds the feed and tag objects.
    class SubscriptionsController < ApiController
      def index
        return if not_modified?(list_etag("subscriptions"))

        expand = expansions(SubscriptionSerializer::EXPANSIONS)
        scope = @user.subscriptions.order(:id)
        scope = scope.includes(feed: [*Feed::ICON_PRELOADS, :touch_icon_image_record]) if expand.include?("feed")
        subscriptions = scope.to_a
        feeds = if expand.include?("feed")
          subscriptions.map(&:feed).uniq(&:id).to_h { [_1.id, FeedSerializer.new(_1).to_h] }
        else
          {}
        end
        tags = tags_by_feed_id

        render_list(subscriptions.map { SubscriptionSerializer.new(_1, tags: tags.fetch(_1.feed_id, []), feed: feeds[_1.feed_id], expand: expand).to_h })
      end

      private

      # {feed_id => [[tag_id, name], ...]}, names in natural order.
      def tags_by_feed_id
        @user.taggings.joins(:tag).pluck(:feed_id, :tag_id, "tags.name")
          .group_by(&:first)
          .transform_values { |rows| rows.map { _1.drop(1) }.uniq.sort_by { _1.last.downcase } }
      end
    end
  end
end
