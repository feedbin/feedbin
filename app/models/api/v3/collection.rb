module Api
  module V3
    # The sidebar's lists as one read model: the system collections in
    # sidebar order, then the user's saved searches. Each knows the table
    # behind it, how its entries are ordered, and which writes it takes.
    class Collection
      attr_reader :id, :kind, :title, :sort, :writes, :query, :saved_search

      SYSTEM = [
        {id: "unread", title: "Unread", sort: "received_desc", writes: %w[state]},
        {id: "all", title: "All", sort: "received_desc", writes: %w[state]},
        {id: "starred", title: "Starred", sort: "added_desc", writes: %w[state]},
        {id: "queue", title: "Airshow", sort: "manual", writes: %w[add remove update clear]},
        {id: "recently_read", title: "Recently Read", sort: "added_desc", writes: %w[add clear]},
        {id: "updated", title: "Updated", sort: "edited_desc", writes: %w[state]},
        {id: "recently_played", title: "Recently Played", sort: "added_desc", writes: %w[add clear]},
        {id: "pages", title: "Pages", sort: "published_desc", writes: %w[state]}
      ].freeze

      RECENTLY_READ_LIMIT = 100
      SEARCH_IDS_LIMIT = 500
      # How long an arrival can take to reach Elasticsearch.
      INDEX_LAG = 5.minutes

      def self.all(user)
        SYSTEM.map { new(user, **_1) } +
          user.saved_searches.order(Arel.sql("lower(name)")).map { new(user, id: "search_#{_1.id}", title: _1.name, sort: "published_desc", writes: [], saved_search: _1) }
      end

      # nil when there is no such collection.
      def self.find(user, id)
        if (match = id.to_s.match(/\Asearch_(\d+)\z/))
          search = user.saved_searches.find_by(id: match[1]) or return nil
          new(user, id: id, title: search.name, sort: "published_desc", writes: [], saved_search: search)
        else
          definition = SYSTEM.find { _1[:id] == id } or return nil
          new(user, **definition)
        end
      end

      def initialize(user, id:, title:, sort:, writes:, saved_search: nil)
        @user = user
        @id = id
        @title = title
        @sort = sort
        @writes = writes
        @saved_search = saved_search
        @kind = saved_search ? "search" : "system"
        @query = saved_search&.query
      end

      def search? = !@saved_search.nil?
      def pages? = @id == "pages"
      def timeline? = @id == "all"
      def accepts?(write) = @writes.include?(write)

      def hidden
        case @id
        when "queue" then @user.setting_on?(:hide_airshow) || !@user.queued_entries.exists?
        when "recently_read" then @user.setting_on?(:hide_recently_read)
        when "updated" then @user.setting_on?(:hide_updated)
        when "recently_played" then @user.setting_on?(:hide_recently_played) || !@user.recently_played_entries.exists?
        when "pages" then !pages.exists?
        else false
        end
      end

      # Pages' entries: the user's Pages feed's, none without one. Its
      # entries are its rows, so it has no membership table.
      def pages
        Entry.where(feed_id: @user.feeds.pages.select(:id))
      end

      # The membership rows, ordered as the collection's sort says, newest or
      # first position first. nil for the timeline, searches and Pages.
      def rows
        case @id
        when "unread" then @user.unread_entries.order(entry_created_at: :desc, entry_id: :desc)
        when "starred" then @user.starred_entries.where.not(entry_id: nil).order(created_at: :desc, entry_id: :desc)
        when "queue" then @user.queued_entries.order(order: :asc, entry_id: :asc)
        when "recently_read" then @user.recently_read_entries.where(id: @user.recently_read_entries.order(id: :desc).limit(RECENTLY_READ_LIMIT).select(:id)).order(id: :desc)
        when "updated" then @user.updated_entries.order(updated_at: :desc, entry_id: :desc)
        when "recently_played" then @user.recently_played_entries.order(created_at: :desc, entry_id: :desc)
        end
      end

      # The column a page is keyed on, and its direction. Microsecond times,
      # or the queue's integer position.
      def key
        case @id
        when "unread" then [:entry_created_at, :desc]
        when "queue" then [:order, :asc]
        when "recently_read" then [:id, :desc]
        when "updated" then [:updated_at, :desc]
        when "pages" then [:published, :desc]
        else [:created_at, :desc]
        end
      end

      # The whole id list, ascending. A saved search's is its unread matches.
      def ids
        @ids ||= if search?
          search_ids
        elsif pages?
          pages.order(:id).pluck(:id)
        else
          rows.reorder(nil).order(:entry_id).pluck(:entry_id)
        end
      end

      # What the id list's ETag is made of: it moves whenever #ids would.
      def ids_version
        if search?
          search_version
        elsif pages?
          pages_version
        else
          Fingerprint.of(rows, :entry_id)
        end
      end

      # One page of the collection's entries in its sort. The timeline and
      # Pages page entries; the rest page their membership rows.
      def page(limit:, cursor: nil)
        column, direction = key
        KeysetPage.new(page_scope, sort: "collection:#{@id}", column: column, direction: direction, limit: limit, cursor: cursor, tiebreak: rows ? :entry_id : :id)
      end

      # The entries on a page, in order, and their memberships by entry id.
      # A membership row whose entry is gone is left out.
      def entries_on(page)
        records = page.records
        unless rows
          return [records, pages? ? records.to_h { [_1.id, membership(_1)] } : {}]
        end
        entries = Entry.where(id: records.map(&:entry_id)).for_api_v3.index_by(&:id)
        listed = records.select { entries.key?(_1.entry_id) }
        [listed.map { entries[_1.entry_id] }, listed.to_h { [_1.entry_id, membership(_1)] }]
      end

      # POST /collections/{id}/entries (see Additions).
      def add(body)
        Additions.new(@user, self, body).call
      end

      # The queue's per-row and bulk writes; the other collections don't take
      # them (accepts?).
      def update_entry(entry_id, body)
        row = @user.queued_entries.find_by!(entry_id: entry_id)
        QueueMembershipWrite.new(row, body).apply
        membership(row.reload)
      end

      def update_entries(rows)
        QueueMembershipWrite.apply_all(@user, rows)
      end

      def remove(entry_id)
        @user.queued_entries.where(entry_id: entry_id).destroy_all
      end

      def clear
        case @id
        when "recently_read" then @user.recently_read_entries.delete_all
        when "recently_played" then RecentlyPlayedEntry.clear_for_user(@user.id)
        when "queue"
          entry_ids = @user.queued_entries.pluck(:entry_id)
          @user.queued_entries.delete_all
          EntryCounterRepair.enqueue(entry_ids)
        end
      end

      # Up to SEARCH_IDS_LIMIT unread matches, the newest published, in id
      # order. Its own query, not the sidebar's badge aggregation, which
      # stops at 50 matches and 50 saved searches. A stored query that no
      # longer parses (Elasticsearch answers 400) matches nothing; any other
      # error raises, so an outage is not cached as an empty list.
      def search_ids
        unread_ids = @user.unread_entries.pluck(:entry_id)
        return [] if unread_ids.empty?
        body = Entry.build_query(user: @user, query: @query, unread_ids: unread_ids)
        bool = body[:query][:bool]
        bool[:filter] = [bool[:filter], {ids: {values: unread_ids}}]
        body = body.slice(:query).merge(sort: [{published: "desc"}, {id: "desc"}])
        response = Search.client { _1.search_after(Search.index_name(Entry.table_name), query: body, size: SEARCH_IDS_LIMIT) }
        if (error = response.data["error"])
          return [] if response.data["status"] == 400
          raise Search::Connection::ResponseError, "Saved search #{@saved_search.id}: #{error}"
        end
        response.ids.sort
      end

      # A page's row is its entry, added when it was saved.
      def membership(row)
        hash = {added_at: row.created_at.utc.iso8601}
        if @id == "queue"
          hash.merge!(
            sort_order: row.order,
            progress_in_seconds: row.progress,
            duration_in_seconds: row.duration,
            playlist_id: row.playlist_id,
            skipped_chapters: Array(row.skipped_chapters)
          )
        end
        hash
      end

      def to_h
        {object: "collection", id: @id, kind: @kind, title: @title, sort: @sort, hidden: hidden, writes: @writes, query: @query}
      end

      private

      def page_scope
        if timeline?
          Entry.where(feed_id: @user.subscriptions.select(:feed_id)).for_api_v3
        elsif pages?
          pages.for_api_v3
        else
          rows
        end
      end

      # A saved search's matches follow the unread list, stars (is:starred),
      # the feeds subscribed to, their tags, and the query, so a quiet poll
      # needs no search. While the newest unread row may still be waiting
      # for Elasticsearch, the ids themselves are part of it too, so the list
      # changes when indexing catches up.
      def search_version
        parts = [
          Fingerprint.of(@user.unread_entries, :entry_id),
          Fingerprint.of(@user.starred_entries, :entry_id),
          Fingerprint.of(@user.subscriptions, :feed_id),
          Fingerprint.of(@user.taggings, :feed_id, :tag_id),
          microseconds(@saved_search.updated_at || @saved_search.created_at)
        ]
        parts << Digest::SHA256.hexdigest(ids.join(","))[0, 32] if @user.unread_entries.where(created_at: INDEX_LAG.ago..).exists?
        parts.join(":")
      end

      # Pages has no membership table: its entries are rows of entries, so
      # the count, the newest id and the newest save move on every add, edit
      # and delete.
      def pages_version
        count, newest_id, updated = pages.pick(Arel.sql("count(*)"), Arel.sql("max(id)"), Arel.sql("max(updated_at)"))
        [count, newest_id || 0, updated ? microseconds(updated) : 0].join(":")
      end

      def microseconds(time)
        (time.to_r * 1_000_000).to_i
      end
    end
  end
end
