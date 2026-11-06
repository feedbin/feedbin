module Api
  module V3
    # Feeds the user subscribes to or has starred, queued, recently read or
    # recently played entries from.
    class FeedList
      def initialize(user)
        @user = user
      end

      # One UNION subquery: Postgres can't turn OR'd IN subqueries into joins and
      # would scan every feed.
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

      # Digest the ids, not the source lists: Recently Read changes on nearly every
      # read and would bust the ETag each poll.
      def version
        newest = feeds.maximum(:updated_at)
        digest = Digest::SHA256.hexdigest(feeds.order(:id).pluck(:id).join(","))[0, 32]
        [digest, newest ? (newest.to_r * 1_000_000).to_i : 0].join(":")
      end
    end
  end
end
