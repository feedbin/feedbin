module Api
  module V3
    # The subscription object: one row of the user's feed list with the feed
    # embedded. feed is the feed's serialized hash, built once per feed; tags
    # is [[id, name], ...] in display order.
    class SubscriptionSerializer
      def initialize(subscription, feed:, tags:)
        @subscription = subscription
        @feed = feed
        @tags = tags
      end

      def to_h
        {
          object: "subscription",
          id: @subscription.id,
          created_at: @subscription.created_at.utc.iso8601,
          title: @subscription.title,
          custom_title: @subscription[:title].presence,
          feed: @feed,
          preferences: {
            muted: @subscription.muted,
            media_only: @subscription.media_only,
            show_updates: @subscription.show_updates
          },
          tags: @tags.map { |id, name| {object: "tag", id: id, name: name} }
        }
      end
    end
  end
end
