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
        else [:created_at, :desc]
        end
      end

      # The whole id list, ascending. A saved search's is its unread matches.
      def ids
        if search?
          search_ids
        elsif pages?
          pages.order(:id).pluck(:id)
        else
          rows.reorder(nil).order(:entry_id).pluck(:entry_id)
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
    end
  end
end
