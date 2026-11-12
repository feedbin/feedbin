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

      # Also called by script/measure_v3_sync.rb. With feeds, the page is read
      # a window of time at a time (WindowedKeysetPage), and scope is the
      # entries before they are narrowed to those feeds.
      def self.page(scope, order, limit:, cursor: nil, feeds: nil)
        column, direction = ORDERS.fetch(order)
        scope = scope.where.not(edited_at: nil) if order == "edited_asc"
        options = {sort: order, column: column, direction: direction, limit: limit, cursor: cursor, key: "timestamp"}
        feeds ? WindowedKeysetPage.new(scope, feeds: feeds, **options) : KeysetPage.new(scope, **options)
      end

      private

      def timeline_base
        Entry.where(feed_id: timeline_feeds)
      end

      def timeline_feeds
        @user.subscriptions.select(:feed_id)
      end

      def streams?
        true
      end

      # A page drawn from every feed of the account, newest first, is read a
      # window of time at a time. A stream starts at its cursor instead, and a
      # page of unread or starred entries starts from the user's own rows,
      # where windows over the feeds would only read around them.
      def windowed?
        order == TIMELINE && boolean_param(:read) != false && boolean_param(:starred) != true
      end

      def render_timeline
        limit = page_limit
        page = timeline_page(limit)
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

      def timeline_page(limit)
        if windowed?
          Timeline.page(filtered(Entry.all).for_api_v3, order, limit: limit, cursor: cursor_fields, feeds: timeline_feeds)
        else
          Timeline.page(filtered_entries.for_api_v3, order, limit: limit, cursor: cursor_fields)
        end
      end

      def filtered_entries
        filtered(timeline_base)
      end

      def filtered(scope)
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
