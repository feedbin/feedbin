module Extension
  module V1
    class SubscriptionsController < ApiController
      def new
        @user = current_user
        @feeds = FeedFinder.feeds(params[:url])
        @subscriptions = @user.existing_subscriptions(@feeds)
        @tag_names = tag_names
      end

      def create
        user = current_user
        urls = params[:feeds].values.map { it["url"] }
        valid_feed_ids = Feed.where(feed_url: urls).pluck(:id)

        @subscriptions = Subscription.create_multiple(params[:feeds].to_unsafe_h, user, valid_feed_ids)

        if @subscriptions.present?
          tags = params[:tags].join(",")
          @subscriptions.each do |subscription|
            subscription.feed.tag(tags, user)
          end
        end
      end

      private

      def tag_names
        @user.taggings
          .where(feed_id: @subscriptions.values.map(&:feed_id))
          .includes(:tag)
          .group_by(&:feed_id)
          .transform_values { |taggings| taggings.map { it.tag.name }.sort }
      end
    end
  end
end