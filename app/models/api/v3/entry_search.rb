module Api
  module V3
    # A search over the user's entries, paged with search_after: the user's
    # query with the structured parameters applied as filters, validated
    # with Elasticsearch before it runs, and one page of entries in search
    # order.
    class EntrySearch
      class QueryInvalid < StandardError; end

      DEFAULT_LIMIT = 50
      MAX_LIMIT = 500
      CURSOR_SORT = "search"

      attr_reader :query

      # query: the user's text. feed_ids/tag_ids: arrays of ids to keep to; an
      # empty feed_ids matches nothing. read/starred: booleans.
      # published_after: a Time. They are filters beside the text rather than
      # tokens appended to it: the query string's default AND does not bind
      # across an OR, so "a OR b feed_id:1" would make the text optional.
      def initialize(user, query:, feed_ids: nil, tag_ids: nil, read: nil, starred: nil, published_after: nil)
        @user = user
        @text = query.to_s.strip
        @feed_ids = feed_ids
        @tag_ids = tag_ids
        @read = read
        @starred = starred
        @published_after = published_after
        @none = feed_ids&.empty?
        @query = display_query
      end

      # The search as one string in the search syntax, tag ids expanded to
      # feed ids. It means what ran; the filters are applied separately.
      def expanded_query
        Entry.replace_tag_ids(@query, @user)
      end

      # => [entries in search order, next sort values or nil, total]
      def page(limit:, after: nil)
        return [[], nil, 0] if @none
        body = request_body
        # false is a query Elasticsearch could not parse; nil is no answer.
        case Search.client { _1.validate(index, query: {query: body[:query]}) }
        when false then raise QueryInvalid, "The query could not be parsed."
        when nil then raise Search::Connection::ResponseError, "Elasticsearch did not validate the query."
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
      # search_after never skips or repeats a hit; the structured parameters
      # as filters.
      def request_body
        body = Entry.build_query(user: @user, query: @text)
        direction = body[:sort]&.first&.values&.first || "desc"
        body[:sort] = body[:sort] ? [*body[:sort], {id: direction}] : [{_score: "desc"}, {id: "desc"}]
        bool = body[:query][:bool]
        filters = [bool[:filter]]
        filters << {terms: {feed_id: @feed_ids}} if @feed_ids.present?
        filters << {terms: {feed_id: @user.taggings.where(tag_id: @tag_ids).distinct.pluck(:feed_id)}} if @tag_ids.present?
        filters << {range: {published: {gt: @published_after.utc.iso8601(6)}}} if @published_after
        unless @read.nil?
          (@read ? bool[:must_not] : filters) << {ids: {values: @user.unread_entries.pluck(:entry_id)}}
        end
        unless @starred.nil?
          (@starred ? filters : bool[:must_not]) << {ids: {values: @user.starred_entries.pluck(:entry_id)}}
        end
        bool[:filter] = filters
        body.except(:from, :size)
      end

      def display_query
        parts = []
        parts << "feed_id:(#{@feed_ids.join(" OR ")})" if @feed_ids.present?
        parts << "tag_id:(#{@tag_ids.join(" OR ")})" if @tag_ids.present?
        parts << (@read ? "is:read" : "is:unread") unless @read.nil?
        parts << (@starred ? "is:starred" : "is:unstarred") unless @starred.nil?
        # The search syntax keeps a range token verbatim, so the time's colons
        # are escaped or they would end the token early.
        parts << "published:>#{@published_after.utc.iso8601.gsub(":", "\\:")}" if @published_after
        text = (parts.any? && @text.match?(/\bOR\b/)) ? "(#{@text})" : @text
        [text, *parts].reject(&:empty?).join(" ")
      end

      # The sort values of the limit-th hit (the page's last), from the raw
      # hits; search_after fetched one more to learn whether more exist.
      def sort_values(response, limit)
        hits = response.data.safe_dig("hits", "hits")
        hits[limit - 1]["sort"]
      end
    end
  end
end
