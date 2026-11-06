module Api
  module V3
    # tags: [[id, name], ...] in display order. feed: the serialized feed hash,
    # needed only with expand=feed.
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

      def title
        @subscription.title.presence || @subscription.feed&.hostname || "Untitled"
      end

      # The columns are nullable and some rows hold NULL; read it as the default.
      def preference(name)
        value = @subscription[name]
        value.nil? ? Subscription.column_defaults.fetch(name.to_s) : value
      end
    end
  end
end
