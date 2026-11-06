module Api
  module V3
    # Feeds are named by feed_url, never id: sequential ids would let anyone
    # subscribe to any feed. Newsletter feed_urls are guessable, so only XML feeds
    # match unless the user can already read the feed. Misses are not_found so
    # they don't reveal that a feed exists.
    class Subscribe
      include BodyFields

      MAX_FEEDS = 5

      attr_reader :body

      def initialize(user, body)
        @user = user
        @body = body
      end

      # => {applied:, skipped:}
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

      # A concurrent duplicate hits the unique index. requires_new so the failed
      # insert rolls back only to a savepoint inside an outer transaction.
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
