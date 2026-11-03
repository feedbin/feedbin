module Api
  module V3
    # POST /subscriptions: subscribing by URL, search words or feed id. A
    # URL is fetched and its feeds discovered; words are searched against
    # known feeds. A feed_id must be one offered to the user (as one of
    # several choices) within a day, or a feed they can already read: feed
    # ids are sequential, and Pages, newsletter and secret-URL feeds are
    # ordinary rows.
    class Subscribe
      include BodyFields

      OFFER_LIFETIME = 1.day

      attr_reader :body

      def initialize(user, body)
        @user = user
        @body = body
      end

      # The feeds the body names: one to subscribe to, several to choose
      # from, or none.
      def feeds
        @feeds ||= begin
          unless body.key?("url") ^ body.key?("feed_id")
            raise Problems::InvalidParameter.new("Send url or feed_id, not both.", pointer: "", code: "invalid_value")
          end
          body.key?("feed_id") ? offered_or_readable(body["feed_id"]) : discover(body["url"].to_s.strip)
        end
      end

      # Several feeds become choices, which a later feed_id may name.
      def offer
        Rails.cache.write_multi(feeds.to_h { [offered_key(_1.id), true] }, expires_in: OFFER_LIFETIME)
      end

      # tag_names apply to a new subscription only. => [subscription, created]
      def subscribe
        subscription = @user.subscriptions.find_or_initialize_by(feed: feeds.first)
        created = subscription.new_record?
        subscription.save!
        SubscriptionList.new(@user).tag(subscription, tag_names) if created && body["tag_names"].present?
        [subscription.reload, created]
      end

      private

      # Any failure finds nothing, as FeedLookup.discover's do.
      def discover(query)
        return FeedLookup.discover(query) if query.start_with?("http") || (query.include?(".") && !query.include?(" "))
        Feed.search(query).to_a
      rescue => exception
        ErrorService.notify(exception)
        []
      end

      def offered_or_readable(id)
        feed = Feed.find_by(id: id) if id.is_a?(Integer)
        (feed && (Rails.cache.exist?(offered_key(feed.id)) || @user.can_read_feed?(feed))) ? [feed] : []
      end

      def offered_key(feed_id)
        "v3:subscriptions:offered:#{@user.id}:#{feed_id}"
      end

      def tag_names
        Array(body["tag_names"]).select { _1.is_a?(String) }
      end
    end
  end
end
