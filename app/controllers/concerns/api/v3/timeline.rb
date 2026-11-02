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

      # One keyset page: entries after a (time, id) position in the order,
      # with the id as tiebreak. script/measure_v3_sync.rb runs it too.
      def self.page(scope, column, direction, limit:, after: nil)
        if after
          operator = (direction == :asc) ? ">" : "<"
          scope = scope.where("(entries.#{column}, entries.id) #{operator} (?, ?)", *after)
        end
        scope.order(column => direction, :id => direction).limit(limit)
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
        scope = filtered_entries
        total = scope.count if boolean_param(:total)

        column, direction = ORDERS.fetch(order)
        scope = scope.where.not(edited_at: nil) if order == "edited_asc"
        entries = Timeline.page(scope.merge(with_associations), column, direction, limit: limit + 1, after: cursor_position).to_a

        more = entries.size > limit
        entries.pop if more
        next_cursor = if more
          cursor_at(entries.last, column)
        elsif STREAMS.include?(order)
          tail_cursor(entries, column)
        end

        meta = {as_of: as_of}
        meta.merge!(stream_cursors(entries)) if streams? && order == TIMELINE && params[:cursor].blank?
        meta[:total] = total if total
        render_list(
          serialize(entries),
          page: page_object(limit: limit, next_cursor: next_cursor, more: more),
          meta: meta
        )
      end

      def cursor_at(entry, column)
        Cursor.encode(sort: order, timestamp: microseconds(entry.public_send(column)), id: entry.id)
      end

      # The default timeline page hands a client its two stream positions, so
      # it can show the newest entries and start following arrivals and edits
      # from there without paging through history. Arrivals resume after the
      # newest entry on the page; edits from the response time, since the
      # page already carries every edit made before it.
      def stream_cursors(entries)
        now = Time.at(Rational(microseconds(Time.now), 1_000_000)).utc
        arrivals = if entries.any?
          Cursor.encode(sort: "received_asc", timestamp: microseconds(entries.first.created_at), id: entries.first.id)
        else
          Cursor.encode(sort: "received_asc", timestamp: microseconds(now), id: 0)
        end
        {
          arrivals_cursor: arrivals,
          edits_cursor: Cursor.encode(sort: "edited_asc", timestamp: microseconds(now), id: 0)
        }
      end

      # A stream's last page still ends with a cursor to resume from: after
      # the last entry, or the cursor the client sent when nothing is new. A
      # stream is only ever entered through a cursor, so one is always there.
      def tail_cursor(entries, column)
        entries.any? ? cursor_at(entries.last, column) : params[:cursor]
      end

      def with_associations
        Entry.with_list_associations.with_renderings.preload(feed: :touch_icon_image_record)
      end

      # With expand=feed, each feed is serialized once per response, however
      # many of its entries are on the page.
      def serialize(entries)
        expand = expansions(EntrySerializer::EXPANSIONS)
        feed_hashes = if expand.include?("feed")
          entries.map(&:feed).uniq(&:id).to_h { [_1.id, FeedSerializer.new(_1).to_h] }
        else
          {}
        end
        entries.map { EntrySerializer.new(_1, feed: feed_hashes[_1.feed_id], expand: expand).to_h }
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

      # A cursor with fields that don't parse is invalid rather than silently
      # restarting.
      # The cursor's (time, id), or nil on a first page.
      def cursor_position
        fields = cursor_fields or return nil
        timestamp, id = fields.values_at("timestamp", "id")
        raise Cursor::Invalid unless timestamp.is_a?(Integer) && id.is_a?(Integer)

        [Time.at(Rational(timestamp, 1_000_000)).utc, id]
      end

      def microseconds(time)
        (time.to_r * 1_000_000).to_i
      end
    end
  end
end
