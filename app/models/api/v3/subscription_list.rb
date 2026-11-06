module Api
  module V3
    class SubscriptionList
      def initialize(user)
        @user = user
      end

      # A row with no kind is an ordinary subscription.
      def subscriptions
        @user.subscriptions.where.not(kind: :generated).or(@user.subscriptions.where(kind: nil))
      end

      def find(id)
        subscriptions.find(id)
      end

      # {feed_id => [[tag_id, name], ...]}, names in natural order.
      def tags_by_feed_id
        @user.taggings.joins(:tag).pluck(:feed_id, :tag_id, "tags.name")
          .group_by(&:first)
          .transform_values { |rows| rows.map { _1.drop(1) }.uniq.sort_by { _1.last.to_s.downcase } }
      end

      # Pass an array, never a joined string: Feed#tag splits strings on commas.
      def tag(subscription, names)
        subscription.feed.tag(names.map(&:strip).reject(&:empty?), @user)
      end
    end
  end
end
