module Api
  module V3
    # Every feed the user can read: the ones they subscribe to, have starred
    # entries from, or have entries from in Airshow's queue, Recently Read or
    # Recently Played. GET /feeds lists it and a feed read checks it.
    class FeedList
      def initialize(user)
        @user = user
      end

      # The ids are a single UNION subquery because Postgres cannot turn two
      # OR'd IN subqueries into joins: it scans every row of feeds, on the
      # 304 path too.
      def feeds
        sources = [
          @user.subscriptions.select(:feed_id),
          @user.starred_entries.select(:feed_id),
          @user.queued_entries.select(:feed_id),
          Entry.where(id: @user.recently_read_entries.select(:entry_id)).select(:feed_id),
          Entry.where(id: @user.recently_played_entries.select(:entry_id)).select(:feed_id)
        ]
        ids = sources.map(&:arel).reduce { |union, query| Arel::Nodes::Union.new(union, query) }
        Feed.where(Feed.arel_table[:id].in(ids))
      end

      def include?(feed)
        feeds.exists?(id: feed.id)
      end

      # A digest of the listed ids, not of the lists they come from: Recently
      # Read changes on nearly every read, and an ETag that followed it would
      # resend every feed each poll. The newest updated_at covers the crawler
      # saving a feed's row.
      def version
        newest = feeds.maximum(:updated_at)
        digest = Digest::SHA256.hexdigest(feeds.order(:id).pluck(:id).join(","))[0, 32]
        [digest, newest ? (newest.to_r * 1_000_000).to_i : 0].join(":")
      end
    end
  end
end
