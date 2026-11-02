module Api
  module V3
    # The subscription object: one row of the user's feed list. The default
    # shape carries feed_id and tag_ids; expand=feed,tags adds the objects.
    # tags is [[id, name], ...] in display order; feed is the feed's
    # serialized hash, built once per feed, needed only with expand=feed.
    class SubscriptionSerializer
      EXPANSIONS = %w[feed tags].freeze

      def initialize(subscription, tags:, feed: nil, expand: [])
        @subscription = subscription
        @tags = tags
        @feed = feed
        @expand = expand
      end

      def to_h
        hash = {
          object: "subscription",
          id: @subscription.id,
          created_at: @subscription.created_at.utc.iso8601,
          title: @subscription.title,
          custom_title: @subscription[:title].presence,
          feed_id: @subscription.feed_id,
          tag_ids: @tags.map(&:first),
          preferences: {
            muted: @subscription.muted,
            media_only: @subscription.media_only,
            show_updates: @subscription.show_updates
          }
        }
        hash[:feed] = @feed if @expand.include?("feed")
        hash[:tags] = @tags.map { |id, name| {object: "tag", id: id, name: name} } if @expand.include?("tags")
        hash
      end
    end
  end
end
