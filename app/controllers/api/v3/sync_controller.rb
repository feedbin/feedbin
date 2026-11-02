module Api
  module V3
    # GET /sync: every list's ETag and a cursor at the newest entry, in one
    # small document, so a poll that finds nothing changed is one 304.
    class SyncController < ApiController
      # A guess at the order of magnitude; design.md open question 9.
      POLL_INTERVAL = 900

      def show
        etags = SyncVersion::LISTS.index_with { list_etag(_1) }
        cursor = entries_cursor
        return if not_modified?(sync_etag(etags, cursor))

        render json: {
          object: "sync",
          as_of: as_of,
          entries_cursor: cursor,
          etags: etags,
          poll_interval_in_seconds: POLL_INTERVAL
        }
      end

      private

      # A received_asc cursor at the newest entry across the user's feeds.
      # Paging GET /entries from it returns what arrived since. One query over
      # the user's feeds, the same work as one timeline page; nil with no entries.
      def entries_cursor
        created_at, id = Entry.where(feed_id: @user.subscriptions.select(:feed_id))
          .order(created_at: :desc, id: :desc)
          .pick(:created_at, :id)
        created_at && Cursor.encode(sort: "received_asc", timestamp: (created_at.to_r * 1_000_000).to_i, id: id)
      end

      def sync_etag(etags, cursor)
        %("sync:#{Digest::SHA256.hexdigest([*etags.values, cursor].join("|"))[0, 32]}")
      end
    end
  end
end
