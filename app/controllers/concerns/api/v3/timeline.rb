module Api
  module V3
    module Timeline
      extend ActiveSupport::Concern

      TIMELINE = "received_desc"
      ORDERS = {
        "received_desc" => [:created_at, :desc],
        "received_asc" => [:created_at, :asc],
        "edited_asc" => [:edited_at, :asc]
      }.freeze
      STREAMS = %w[received_asc edited_asc].freeze

      # Also called by script/measure_v3_sync.rb.
      def self.page(scope, order, limit:, cursor: nil)
        column, direction = ORDERS.fetch(order)
        scope = scope.where.not(edited_at: nil) if order == "edited_asc"
        KeysetPage.new(scope, sort: order, column: column, direction: direction, limit: limit, cursor: cursor, key: "timestamp")
      end

      private

      def timeline_base
        Entry.where(feed_id: @user.subscriptions.select(:feed_id))
      end

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

      # Edits resume from now: the page already reflects every earlier edit.
      def stream_cursors(entries)
        now = microseconds(Time.now)
        arrivals = entries.any? ? [microseconds(entries.first.created_at), entries.first.id] : [now, 0]
        {
          arrivals_cursor: Cursor.encode(sort: "received_asc", timestamp: arrivals.first, id: arrivals.last),
          edits_cursor: Cursor.encode(sort: "edited_asc", timestamp: now, id: 0)
        }
      end

      # Streams are only entered through a cursor, so params[:cursor] is present.
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
