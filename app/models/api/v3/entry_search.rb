module Api
  module V3
    # A search over the user's entries, paged with search_after: the query
    # string with the structured parameters folded in, validated with
    # Elasticsearch before it runs, and one page of entries in search order.
    class EntrySearch
      class QueryInvalid < StandardError; end

      DEFAULT_LIMIT = 50
      MAX_LIMIT = 500
      CURSOR_SORT = "search"

      attr_reader :query

      # query: the user's text. feed_ids/tag_ids: arrays folded in as
      # feed_id:(…)/tag_id:(…); an empty feed_ids matches nothing.
      # read/starred: booleans folded in as is: filters. published_after: a
      # Time folded in as published:>.
      def initialize(user, query:, feed_ids: nil, tag_ids: nil, read: nil, starred: nil, published_after: nil)
        @user = user
        @none = feed_ids&.empty?
        parts = [query.to_s.strip]
        parts << "feed_id:(#{feed_ids.join(" OR ")})" if feed_ids.present?
        parts << "tag_id:(#{tag_ids.join(" OR ")})" if tag_ids.present?
        parts << (read ? "is:read" : "is:unread") unless read.nil?
        parts << (starred ? "is:starred" : "is:unstarred") unless starred.nil?
        # The search syntax keeps a range token verbatim, so the time's colons
        # are escaped or they would end the token early.
        parts << "published:>#{published_after.utc.iso8601.gsub(":", "\\:")}" if published_after
        @query = parts.reject(&:empty?).join(" ")
      end

      # The query as it ran: tag ids expanded to feed ids.
      def expanded_query
        Entry.replace_tag_ids(@query, @user)
      end

      # => [entries in search order, next sort values or nil, total]
      def page(limit:, after: nil)
        return [[], nil, 0] if @none
        body = request_body
        unless Search.client { _1.validate(index, query: {query: body[:query]}) }
          raise QueryInvalid, "The query could not be parsed."
        end
        response = Search.client { _1.search_after(index, query: body, size: limit + 1, after: after) }
        ids = response.ids
        more = ids.size > limit
        ids = ids.first(limit)
        entries = Entry.where(id: ids).with_list_associations.with_renderings.preload(feed: :touch_icon_image_record).index_by(&:id)
        after = more ? sort_values(response, limit) : nil
        [ids.filter_map { entries[_1] }, after, response.total]
      end

      private

      def index
        Search.index_name(Entry.table_name)
      end

      # build_query's sort, or relevance, with the entry id as a tiebreak so
      # search_after never skips or repeats a hit.
      def request_body
        body = Entry.build_query(user: @user, query: @query)
        direction = body[:sort]&.first&.values&.first || "desc"
        body[:sort] = body[:sort] ? [*body[:sort], {id: direction}] : [{_score: "desc"}, {id: "desc"}]
        body.except(:from, :size)
      end

      # The sort values of the limit-th hit (the page's last), from the raw
      # hits; search_after fetched one more to learn whether more exist.
      def sort_values(response, limit)
        hits = response.instance_variable_get(:@data).safe_dig("hits", "hits")
        hits[limit - 1]["sort"]
      end
    end
  end
end
