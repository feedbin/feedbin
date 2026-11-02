module Api
  module V3
    # The sidebar's collections: the list, each one's whole id list, its
    # entries with membership, and the membership writes the plain lists take
    # (Recently Read, Recently Played, Airshow). Unread, Starred and Updated
    # are written with the state verbs instead.
    class CollectionsController < ApiController
      include SearchPage

      MAX_IDS = 1_000
      ADDABLE = {
        "recently_read" => :add_recently_read,
        "recently_played" => :add_recently_played,
        "queue" => :add_queued
      }.freeze

      def index
        data = Collection.all(@user).map(&:to_h)
        return if not_modified?(etag_for("collections", Digest::SHA256.hexdigest(JSON.generate(data))[0, 32]))
        render_list(data)
      end

      def ids
        return status_not_found if collection.timeline?
        return if not_modified?(ids_etag)
        render_list(collection.ids)
      end

      def entries
        return render_search_page(EntrySearch.new(@user, query: collection.query)) if collection.search?
        limit = page_limit
        if collection.timeline?
          render_timeline_page(limit)
        else
          render_membership_page(limit)
        end
      end

      # POST /collections/{id}/entries
      def add
        return rejects("add") unless collection.accepts?("add")
        ids = ids_param(request.request_parameters["ids"])
        queue_playlist_id if collection.id == "queue"
        permissions = EntryAccess.new(@user).permissions_for(ids)
        applied = []
        skipped = []
        ids.each do |id|
          permission = permissions[id]
          reason = permission.found? ? (send(ADDABLE.fetch(collection.id), permission) ? nil : "not_subscribed") : "not_found"
          reason ? skipped << {id: id, reason: reason} : applied << id
        end
        render json: {applied: applied, skipped: skipped}
      end

      # DELETE /collections/{id}/entries/{entry_id}
      def remove
        return rejects("remove") unless collection.accepts?("remove")
        @user.queued_entries.where(entry_id: params[:entry_id]).destroy_all
        head :no_content
      end

      # PATCH /collections/{id}/entries/{entry_id}
      def update
        return rejects("update") unless collection.accepts?("update")
        row = @user.queued_entries.find_by!(entry_id: params[:entry_id])
        QueueMembershipWrite.new(row, request.request_parameters).apply
        render json: collection.membership(row.reload)
      end

      # PATCH /collections/{id}/entries
      def bulk
        return rejects("update") unless collection.accepts?("update")
        rows = request.request_parameters["entries"]
        unless rows.is_a?(Array) && rows.all? { _1.is_a?(Hash) && _1["id"].is_a?(Integer) }
          raise Problems::InvalidParameter.new("entries must be an array of objects with an id.", pointer: "/entries", code: "invalid_value")
        end
        raise Problems::InvalidParameter.new("entries takes at most #{MAX_IDS} rows.", pointer: "/entries", code: "too_many") if rows.size > MAX_IDS

        queued = @user.queued_entries.where(entry_id: rows.map { _1["id"] }).index_by(&:entry_id)
        applied = []
        skipped = []
        ActiveRecord::Base.transaction do
          rows.each_with_index do |body, index|
            row = queued[body["id"]]
            next skipped << {id: body["id"], reason: "not_found"} unless row
            # A row whose every sent field was stale is skipped; one that sent
            # nothing to change has nothing stale and is applied.
            written, stale = QueueMembershipWrite.new(row, body, pointer: "/entries/#{index}").apply
            (written.empty? && stale.any?) ? skipped << {id: body["id"], reason: "stale_write"} : applied << body["id"]
          end
        end
        render json: {applied: applied, skipped: skipped}
      end

      # DELETE /collections/{id}/entries
      def clear
        return rejects("clear") unless collection.accepts?("clear")
        case collection.id
        when "recently_read" then @user.recently_read_entries.delete_all
        when "recently_played" then RecentlyPlayedEntry.clear_for_user(@user.id)
        when "queue"
          entry_ids = @user.queued_entries.pluck(:entry_id)
          @user.queued_entries.delete_all
          EntryCounterRepair.enqueue(entry_ids)
        end
        head :no_content
      end

      private

      def collection
        @collection ||= Collection.find(@user, params[:id]) || raise(ActiveRecord::RecordNotFound)
      end

      def ids_etag
        if collection.search?
          # Matches follow the unread list, stars (is:starred), the feeds
          # subscribed to, and the query.
          search = collection.saved_search
          etag_for(collection.id, versions.fetch("unread"), versions.fetch("starred"), versions.fetch("subscriptions"), ((search.updated_at || search.created_at).to_r * 1_000_000).to_i)
        else
          list_etag(collection.id)
        end
      end

      def rejects(write)
        raise Problems::InvalidParameter.new("The #{collection.id} collection does not accept #{write}.", pointer: "id", code: "invalid_value")
      end

      def ids_param(value)
        unless value.is_a?(Array) && value.any? && value.all? { _1.is_a?(Integer) && _1.positive? }
          raise Problems::InvalidParameter.new("ids must be an array of entry ids.", pointer: "/ids", code: "invalid_value")
        end
        raise Problems::InvalidParameter.new("ids takes at most #{MAX_IDS} ids.", pointer: "/ids", code: "too_many") if value.size > MAX_IDS
        value.uniq
      end

      # Each takes the EntryAccess permission add already looked up for every
      # id at once.
      def add_recently_read(permission)
        return false unless permission.writable?
        RecentlyReadEntry.create_from_owners(@user, permission.entry.id)
        true
      end

      # Airshow plays episodes of podcasts the reader may not subscribe to,
      # so a podcast subscription or a queued episode is enough, as the web's
      # can_read_entry? allows the queue.
      def add_recently_played(permission)
        @queued_ids ||= @user.queued_entries.pluck(:entry_id).to_set
        return false unless permission.writable? || permission.queueable || @queued_ids.include?(permission.entry.id)
        RecentlyPlayedEntry.create_or_find_by(user_id: @user.id, entry_id: permission.entry.id)
        true
      end

      # Queueing needs the podcast subscription Airshow keeps, not the reader's.
      def add_queued(permission)
        return false unless permission.queueable
        entry = permission.entry
        playlist_id = queue_playlist_id
        row = @user.queued_entries.create_with(feed_id: entry.feed_id, playlist_id: playlist_id).create_or_find_by(entry_id: entry.id)
        row.update!(playlist_id: playlist_id) if playlist_id && row.playlist_id != playlist_id
        true
      end

      # Checked before any id is added, so a bad playlist writes nothing.
      def queue_playlist_id
        return @queue_playlist_id if defined?(@queue_playlist_id)
        playlist_id = request.request_parameters["playlist_id"]
        raise Problems::InvalidParameter.new("playlist_id must be an integer.", pointer: "/playlist_id", code: "invalid_value") unless playlist_id.nil? || playlist_id.is_a?(Integer)
        raise Problems::InvalidParameter.new("playlist_id must be one of the user's playlists.", pointer: "/playlist_id", code: "invalid_value") unless playlist_id.nil? || @user.playlists.exists?(id: playlist_id)
        @queue_playlist_id = playlist_id
      end

      # A page of membership rows, keyed on the collection's sort column and
      # the entry id, then the entries for them in row order.
      def render_membership_page(limit)
        column, direction = collection.key
        rows = collection.rows
        if (fields = cursor_fields)
          raise Cursor::Invalid unless fields["sort"] == "collection:#{collection.id}" && fields["key"].is_a?(Integer) && fields["id"].is_a?(Integer)
          operator = (direction == :asc) ? ">" : "<"
          value = integer_key?(column) ? fields["key"] : Time.at(Rational(fields["key"], 1_000_000)).utc
          table = rows.model.table_name
          rows = rows.where("(#{table}.#{column}, #{table}.entry_id) #{operator} (?, ?)", value, fields["id"])
        end
        rows = rows.limit(limit + 1).to_a
        more = rows.size > limit
        rows.pop if more
        next_cursor = more && Cursor.encode(sort: "collection:#{collection.id}", key: key_value(rows.last, column), id: rows.last.entry_id)

        entries = Entry.where(id: rows.map(&:entry_id)).merge(entry_associations).index_by(&:id)
        expand = expansions(EntrySerializer::EXPANSIONS)
        feeds = expand.include?("feed") ? entries.values.map(&:feed).uniq(&:id).to_h { [_1.id, FeedSerializer.new(_1).to_h] } : {}
        data = rows.filter_map do |row|
          entry = entries[row.entry_id] or next
          EntrySerializer.new(entry, feed: feeds[entry.feed_id], expand: expand, membership: collection.membership(row)).to_h
        end
        render_list(data, page: page_object(limit: limit, next_cursor: next_cursor || nil, more: more), meta: {as_of: as_of})
      end

      # `all` is the timeline, with no membership.
      def render_timeline_page(limit)
        scope = Entry.where(feed_id: @user.subscriptions.select(:feed_id))
        if (fields = cursor_fields)
          raise Cursor::Invalid unless fields["sort"] == "collection:all" && fields["key"].is_a?(Integer) && fields["id"].is_a?(Integer)
          scope = scope.where("(entries.created_at, entries.id) < (?, ?)", Time.at(Rational(fields["key"], 1_000_000)).utc, fields["id"])
        end
        entries = scope.merge(entry_associations).order(created_at: :desc, id: :desc).limit(limit + 1).to_a
        more = entries.size > limit
        entries.pop if more
        next_cursor = more && Cursor.encode(sort: "collection:all", key: (entries.last.created_at.to_r * 1_000_000).to_i, id: entries.last.id)
        expand = expansions(EntrySerializer::EXPANSIONS)
        feeds = expand.include?("feed") ? entries.map(&:feed).uniq(&:id).to_h { [_1.id, FeedSerializer.new(_1).to_h] } : {}
        data = entries.map { EntrySerializer.new(_1, feed: feeds[_1.feed_id], expand: expand).to_h }
        render_list(data, page: page_object(limit: limit, next_cursor: next_cursor || nil, more: more), meta: {as_of: as_of})
      end

      def entry_associations
        Entry.with_list_associations.with_renderings.preload(feed: :touch_icon_image_record)
      end

      def integer_key?(column)
        %i[order id].include?(column)
      end

      def key_value(row, column)
        value = row.public_send(column)
        integer_key?(column) ? value.to_i : (value.to_r * 1_000_000).to_i
      end
    end
  end
end
