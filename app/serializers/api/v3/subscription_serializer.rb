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
          title: title,
          custom_title: @subscription[:title].presence,
          feed_id: @subscription.feed_id,
          tag_ids: @tags.map(&:first),
          preferences: {
            muted: preference(:muted),
            media_only: preference(:media_only),
            show_updates: preference(:show_updates)
          }
        }
        hash[:feed] = @feed if @expand.include?("feed")
        hash[:tags] = @tags.map { |id, name| {object: "tag", id: id, name: name.to_s} } if @expand.include?("tags")
        hash
      end

      private

      # The effective title, never null: the user's, else the feed's, else
      # where the feed lives. "Untitled" is the web app's word for a feed
      # that has none of them (Feed.include_user_title).
      def title
        @subscription.title.presence || @subscription.feed&.hostname || "Untitled"
      end

      # The columns are nullable, and some rows hold NULL (the add-feed form
      # used to write one for an unchecked box). NULL reads as the column's
      # default.
      def preference(name)
        value = @subscription[name]
        value.nil? ? Subscription.column_defaults.fetch(name.to_s) : value
      end
    end
  end
end
