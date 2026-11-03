# The timeline: entries newest received first, with the filters, the cursor
# that carries its own order, the two stream cursors on the first page, and
# the tail cursor on a stream's last page. GET /entries and
# GET /feeds/{id}/entries share it; a controller sets the base scope and
# whether the page hands out stream cursors.
module Api
  module V3
    module Timeline
      extend ActiveSupport::Concern

      # There is no sort parameter. The timeline is newest received first, and
      # a cursor carries its own order: a timeline page continues the
      # timeline, and the two stream cursors a timeline page hands out
      # (meta.arrivals_cursor, meta.edits_cursor) follow arrivals and edits
      # oldest first. A stream's last page still ends with a cursor
      # (tail_cursor).
      TIMELINE = "received_desc"
      ORDERS = {
        "received_desc" => [:created_at, :desc],
        "received_asc" => [:created_at, :asc],
        "edited_asc" => [:edited_at, :asc]
      }.freeze
      STREAMS = %w[received_asc edited_asc].freeze

      # One keyset page of the timeline in an order. script/measure_v3_sync.rb
      # runs it too.
      def self.page(scope, order, limit:, cursor: nil)
        column, direction = ORDERS.fetch(order)
        scope = scope.where.not(edited_at: nil) if order == "edited_asc"
        KeysetPage.new(scope, sort: order, column: column, direction: direction, limit: limit, cursor: cursor, key: "timestamp")
      end

      private

      # The entries the timeline draws from. Overridden for one feed.
      def timeline_base
        Entry.where(feed_id: @user.subscriptions.select(:feed_id))
      end

      # Whether the first page carries meta.arrivals_cursor and
      # meta.edits_cursor. Only the whole timeline does.
      def streams?
        true
      end

      def render_timeline
        limit = page_limit
        page = Timeline.page(filtered_entries.for_api_v3, order, limit: limit, cursor: cursor_fields)
        entries = page.records
        next_cursor = page.next_cursor || (tail_cursor(page) if STREAMS.include?(order))

        render_list(
          serialize_entries(entries),
          page: page_object(limit: limit, next_cursor: next_cursor, more: page.more?),
          meta: timeline_meta(entries)
        )
      end

      def timeline_meta(entries)
        meta = {as_of: as_of}
        meta.merge!(stream_cursors(entries)) if streams? && order == TIMELINE && params[:cursor].blank?
        meta[:total] = filtered_entries.count if boolean_param(:total)
        meta
      end

      # The default timeline page hands a client its two stream positions, so
      # it can show the newest entries and start following arrivals and edits
      # from there without paging through history. Arrivals resume after the
      # newest entry on the page; edits from the response time, since the
      # page already carries every edit made before it.
      def stream_cursors(entries)
        now = microseconds(Time.now)
        arrivals = entries.any? ? [microseconds(entries.first.created_at), entries.first.id] : [now, 0]
        {
          arrivals_cursor: Cursor.encode(sort: "received_asc", timestamp: arrivals.first, id: arrivals.last),
          edits_cursor: Cursor.encode(sort: "edited_asc", timestamp: now, id: 0)
        }
      end

      # A stream's last page still ends with a cursor to resume from: after
      # the last entry, or the cursor the client sent when nothing is new. A
      # stream is only ever entered through a cursor, so one is always there.
      def tail_cursor(page)
        page.records.any? ? page.cursor_at(page.records.last) : params[:cursor]
      end

      def filtered_entries
        scope = timeline_base

        case boolean_param(:read)
        when true then scope = scope.where.not(id: @user.unread_entries.select(:entry_id))
        when false then scope = scope.where(id: @user.unread_entries.select(:entry_id))
        end

        case boolean_param(:starred)
        when true then scope = scope.where(id: @user.starred_entries.select(:entry_id))
        when false then scope = scope.where.not(id: @user.starred_entries.select(:entry_id))
        end

        if (time = time_param(:received_after))
          scope = scope.where("entries.created_at > ?", time)
        end

        scope
      end

      # The order comes from the cursor; without one, the timeline.
      def order
        @order ||= begin
          fields = cursor_fields
          value = fields ? fields["sort"] : TIMELINE
          raise Cursor::Invalid unless ORDERS.key?(value)
          value
        end
      end

      def microseconds(time)
        (time.to_r * 1_000_000).to_i
      end
    end
  end
end
