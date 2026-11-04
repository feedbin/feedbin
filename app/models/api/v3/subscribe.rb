module Api
  module V3
    # POST /subscriptions: subscribe to several feeds at once, each with an
    # optional custom title, with tag_names applied to every new one. A
    # feed_id must be one GET /subscriptions/new offered the user within a
    # day, or a feed they can already read: feed ids are sequential, and
    # Pages, newsletter and secret-URL feeds are ordinary rows. Any other id
    # is skipped as not_found, so an id that wasn't offered doesn't reveal
    # that a feed exists.
    class Subscribe
      include BodyFields

      OFFER_LIFETIME = 1.day
      # Find offers a handful of feeds; the cap only bounds abuse. A guess:
      # see design.md, Open questions.
      MAX_FEEDS = 100

      attr_reader :body

      def self.offer(user, feeds)
        return if feeds.empty?
        Rails.cache.write_multi(feeds.to_h { [offered_key(user, it.id), true] }, expires_in: OFFER_LIFETIME)
      end

      def self.offered_key(user, feed_id)
        "v3:subscriptions:offered:#{user.id}:#{feed_id}"
      end

      def initialize(user, body)
        @user = user
        @body = body
      end

      # A feed the user already subscribes to, directly or through a feed that
      # redirected to it, is applied and left alone. Each new subscription is
      # its own transaction with its taggings. => {applied:, skipped:}
      def subscribe
        items = feed_items
        tags = tag_names
        feeds = Feed.where(id: items.map(&:first)).index_by(&:id)
        allowed = feeds.values.select { allowed?(it) }
        existing = @user.existing_subscriptions(allowed)

        items.each_with_object({applied: [], skipped: []}) do |(feed_id, title), report|
          feed = feeds[feed_id]
          unless feed && allowed.include?(feed)
            report[:skipped] << {id: feed_id, reason: "not_found"}
            next
          end
          create(feed, title, tags) unless existing[feed.id] || existing[feed.feed_url]
          report[:applied] << feed.id
        end
      end

      private

      # => [[feed_id, title or nil]]
      def feed_items
        list = body["feeds"]
        raise invalid("feeds", "missing", "feeds is required.") if list.nil?
        raise invalid("feeds", "invalid_value", "feeds must be a non-empty array.") unless list.is_a?(Array) && list.any?
        raise invalid("feeds", "too_many", "feeds takes at most #{MAX_FEEDS} feeds.") if list.size > MAX_FEEDS

        seen = Set.new
        list.each_with_index.map do |item, index|
          object("feeds/#{index}", item)
          feed_id = item["feed_id"]
          raise invalid("feeds/#{index}/feed_id", "invalid_value", "feed_id must be an integer.") unless feed_id.is_a?(Integer)
          raise invalid("feeds/#{index}/feed_id", "conflict", "feed_id #{feed_id} appears more than once.") unless seen.add?(feed_id)
          [feed_id, optional_string("feeds/#{index}/custom_title", item["custom_title"])&.strip.presence]
        end
      end

      def tag_names
        return [] unless body.key?("tag_names")
        strings("tag_names")
      end

      def allowed?(feed)
        offered.include?(feed.id) || @user.can_read_feed?(feed)
      end

      def offered
        @offered ||= begin
          keys = body["feeds"].map { self.class.offered_key(@user, it["feed_id"]) }
          Rails.cache.read_multi(*keys).keys.map { it.split(":").last.to_i }
        end
      end

      # Two requests at once (a double-tapped Add) both pass the existing
      # check; the unique index stops the second, which is already
      # subscribed. requires_new, so the failed insert rolls back to a
      # savepoint when this runs inside another transaction.
      def create(feed, title, tags)
        Subscription.transaction(requires_new: true) do
          subscription = @user.subscriptions.create!(feed: feed, title: title)
          SubscriptionList.new(@user).tag(subscription, tags) if tags.any?
        end
      rescue ActiveRecord::RecordNotUnique
        nil
      end
    end
  end
end
