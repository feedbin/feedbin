module Api
  module V3
    # The user's subscriptions as v3 lists them, and their tags.
    class SubscriptionList
      def initialize(user)
        @user = user
      end

      # Generated subscriptions (Pages) aren't subscriptions in v3: Pages is a
      # collection. A row with no kind is an ordinary one.
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

      # Replaces the subscription's tags. Blank names are skipped. An array,
      # never joined: Feed#tag splits a string on commas, and a folder name
      # may contain one.
      def tag(subscription, names)
        subscription.feed.tag(names.map(&:strip).reject(&:empty?), @user)
      end
    end
  end
end
