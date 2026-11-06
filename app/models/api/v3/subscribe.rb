module Api
  module V3
    # POST /subscriptions: subscribe to several feeds at once, each with an
    # optional custom title, with tag_names applied to every new one.
    #
    # Each feed is named by its feed_url exactly as POST /subscriptions/new
    # returned it, not by id: ids are sequential, so an id would let anyone
    # subscribe to any feed. Knowing a URL grants only what Find feeds
    # already would, since Find returns a known feed for its URL, and a
    # password-protected feed keeps its credentials in feed_url. Only XML
    # feeds match: a newsletter's feed_url (sender domain and feed id) can
    # be guessed. A Pages or newsletter feed the user can already read
    # matches too. Any other URL is skipped as not_found, so it doesn't
    # reveal that a feed exists. Nothing is stored between the two steps.
    class Subscribe
      include BodyFields

      # Find returns a handful of feeds: a search returns three, and a site
      # rarely links more. Five covers those with room, and bounds abuse.
      MAX_FEEDS = 5

      attr_reader :body

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
        feeds = Feed.where(feed_url: items.map(&:first)).select { allowed?(it) }.index_by(&:feed_url)
        existing = @user.existing_subscriptions(feeds.values)

        items.each_with_object({applied: [], skipped: []}) do |(feed_url, title), report|
          feed = feeds[feed_url]
          unless feed
            report[:skipped] << {feed_url: feed_url, reason: "not_found"}
            next
          end
          create(feed, title, tags) unless existing[feed.id] || existing[feed.feed_url]
          report[:applied] << feed.id
        end
      end

      private

      # => [[feed_url, title or nil]]
      def feed_items
        list = body["feeds"]
        raise invalid("feeds", "missing", "feeds is required.") if list.nil?
        raise invalid("feeds", "invalid_value", "feeds must be a non-empty array.") unless list.is_a?(Array) && list.any?
        raise invalid("feeds", "too_many", "feeds takes at most #{MAX_FEEDS} feeds.") if list.size > MAX_FEEDS

        seen = Set.new
        list.each_with_index.map do |item, index|
          object("feeds/#{index}", item)
          feed_url = item["feed_url"]
          raise invalid("feeds/#{index}/feed_url", "invalid_value", "feed_url must be a non-empty string.") unless feed_url.is_a?(String) && feed_url.present?
          raise invalid("feeds/#{index}/feed_url", "conflict", "#{feed_url} appears more than once.") unless seen.add?(feed_url)
          [feed_url, optional_string("feeds/#{index}/title", item["title"])&.strip.presence]
        end
      end

      def tag_names
        return [] unless body.key?("tag_names")
        strings("tag_names")
      end

      def allowed?(feed)
        feed.xml? || @user.can_read_feed?(feed)
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
