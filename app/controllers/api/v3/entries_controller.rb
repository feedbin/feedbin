module Api
  module V3
    # GET /entries: the timeline, the entries whose content changed, or a
    # set of entries by id. There is no GET /entries/{id}; ids= covers it.
    class EntriesController < ApiController
      MAX_IDS = 500

      # Each sort's column and direction. edited_after= has its own: edits in
      # the order they happened, so a client catches up from where it was.
      SORTS = {
        "received_desc" => [:created_at, :desc],
        "published_desc" => [:published, :desc],
        "edited_asc" => [:edited_at, :asc]
      }.freeze

      def index
        params.key?(:ids) ? render_ids : render_timeline
      end

      private

      # Not paginated. Ids that don't exist or the user can't read come back
      # in meta.missing, so a client can drop them from its cache.
      def render_ids
        ids = requested_ids
        readable = @user.can_read_filter(ids)
        entries = Entry.where(id: readable).merge(with_associations).index_by(&:id)
        render_list(
          serialize(ids.filter_map { entries[_1] }),
          meta: {missing: ids - entries.keys}
        )
      end

      def render_timeline
        limit = page_limit
        scope = filtered_entries
        total = scope.count if boolean_param(:total)

        column, direction = SORTS.fetch(sort)
        scope = after_cursor(scope, column, direction)
        entries = scope.merge(with_associations)
          .order(column => direction, :id => direction)
          .limit(limit + 1)
          .to_a

        next_cursor = if entries.size > limit
          entries.pop
          last = entries.last
          Cursor.encode(sort: sort, timestamp: microseconds(last.public_send(column)), id: last.id)
        end

        meta = total ? {total: total} : {}
        render_list(
          serialize(entries),
          page: page_object(limit: limit, next_cursor: next_cursor),
          meta: meta
        )
      end

      def with_associations
        Entry.with_list_associations.preload(feed: :touch_icon_image_record)
      end

      # Each feed is serialized once per response, however many of its
      # entries are on the page.
      def serialize(entries)
        feeds = entries.map(&:feed).uniq(&:id)
        stats = FeedStat.daily_counts(feed_ids: feeds.map(&:id), interval: "27 days")
        feed_hashes = feeds.to_h do |feed|
          posts_per_week = ((stats[feed.id]&.volume || 0) / 4.0).round(1)
          [feed.id, FeedSerializer.new(feed, posts_per_week: posts_per_week).to_h]
        end
        entries.map { EntrySerializer.new(_1, feed: feed_hashes[_1.feed_id]).to_h }
      end

      def filtered_entries
        scope = Entry.where(feed_id: @user.subscriptions.select(:feed_id))

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

        if (time = time_param(:edited_after))
          scope = scope.where("entries.edited_at > ?", time)
        end

        scope
      end

      def sort
        @sort ||= if params.key?(:edited_after)
          "edited_asc"
        else
          value = params.fetch(:sort, "received_desc")
          unless %w[received_desc published_desc].include?(value)
            raise Problems::InvalidParameter.new("sort must be received_desc or published_desc.", pointer: "sort", code: "invalid_value")
          end
          value
        end
      end

      # A cursor from a different sort, or with fields that don't parse, is
      # invalid rather than silently restarting.
      def after_cursor(scope, column, direction)
        fields = cursor_fields or return scope
        timestamp, id = fields.values_at("timestamp", "id")
        unless fields["sort"] == sort && timestamp.is_a?(Integer) && id.is_a?(Integer)
          raise Cursor::Invalid
        end

        operator = (direction == :asc) ? ">" : "<"
        scope.where("(entries.#{column}, entries.id) #{operator} (?, ?)", Time.at(Rational(timestamp, 1_000_000)).utc, id)
      end

      def requested_ids
        ids = params[:ids].to_s.split(",").map { Integer(_1.strip, exception: false) }
        if ids.empty? || ids.any? { _1.nil? || _1 <= 0 }
          raise Problems::InvalidParameter.new("ids must be comma-separated entry ids.", pointer: "ids", code: "invalid_value")
        end
        if ids.size > MAX_IDS
          raise Problems::InvalidParameter.new("ids takes at most #{MAX_IDS} ids.", pointer: "ids", code: "too_many")
        end
        ids.uniq
      end

      def boolean_param(name)
        return nil unless params.key?(name)
        case params[name]
        when "true" then true
        when "false" then false
        else raise Problems::InvalidParameter.new("#{name} must be true or false.", pointer: name.to_s, code: "invalid_value")
        end
      end

      def time_param(name)
        return nil unless params.key?(name)
        Time.iso8601(params[name].to_s)
      rescue ArgumentError
        raise Problems::InvalidParameter.new("#{name} must be an RFC 3339 timestamp.", pointer: name.to_s, code: "invalid_value")
      end

      def microseconds(time)
        (time.to_r * 1_000_000).to_i
      end
    end
  end
end
