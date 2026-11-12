module Api
  module V3
    # A newest-first KeysetPage of the entries of many feeds.
    #
    # No index orders entries across feeds, so the plain query reads every
    # entry the feeds hold before the cursor to find the newest page of them.
    # This reads only a window of time beside the cursor, each feed through
    # the (feed_id, created_at, id) index, and widens the window until it
    # holds the page.
    #
    # A window with more than a page of entries in it gives the page exactly:
    # everything outside it is older than everything in it. A window with
    # less proves nothing, so when none holds a page the plain query answers,
    # as it does for the last page of a timeline.
    class WindowedKeysetPage < KeysetPage
      WINDOWS = [6.hours, 2.days, 16.days, 128.days, 1024.days].freeze

      # scope: the entries, not narrowed to any feed. feeds: a relation whose
      # one column is feed_id.
      def initialize(scope, feeds:, **options)
        super(scope.where(feed_id: feeds), **options)
        raise ArgumentError, "a windowed page reads newest first" unless @direction == :desc
        @entries = scope
        @feeds = feeds
      end

      private

      # Rows can leave a window between its count and its read, so a read
      # that comes back short is no more trusted than a window never found.
      def fetch
        rows = (from = window) ? page_of(windowed(from)).to_a : []
        (rows.size > @limit) ? rows : super
      end

      # Where the narrowest window holding more than a page begins.
      def window
        newest = position&.first || Time.current
        WINDOWS.lazy.map { newest - _1 }.find { windowed(_1).limit(@limit + 1).count > @limit }
      end

      # The entries from a time up to the cursor, read feed by feed. No feed
      # can put more than a page of rows on the page, so none is read further.
      def windowed(from)
        table = @entries.connection.quote_table_name(@entries.model.table_name)
        since = @entries.model.arel_table[@column].gteq(from)
        per_feed = page_of(after_cursor(@entries).where(since).where("#{table}.feed_id = page_feeds.feed_id"))
        @entries.unscope(:where).from("(#{@feeds.to_sql}) page_feeds CROSS JOIN LATERAL (#{per_feed.to_sql}) #{table}")
      end
    end
  end
end
