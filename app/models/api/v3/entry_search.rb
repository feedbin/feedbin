module Api
  module V3
    class EntrySearch
      class QueryInvalid < StandardError; end

      DEFAULT_LIMIT = 50
      MAX_LIMIT = 500
      CURSOR_SORT = "search"

      attr_reader :query

      # An empty feed_ids matches nothing. Parameters are filters, not query tokens:
      # the default AND doesn't bind across OR, so "a OR b feed_id:1" lets a match any feed.
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

      # The search as one string in the search syntax, tag ids expanded to feed ids.
      def expanded_query
        Entry.replace_tag_ids(@query, @user)
      end

      # => [entries in search order, next sort values or nil, total]
      def page(limit:, after: nil)
        return [[], nil, 0] if @none
        body = request_body
        # false: unparseable query; nil: no answer.
        case Search.client { _1.validate(index, query: {query: body[:query]}) }
        when false then raise QueryInvalid, "The query could not be parsed."
        when nil then raise Search::Connection::ResponseError, "Elasticsearch did not validate the query."
        end
        response = Search.client { _1.search_after(index, query: body, size: limit + 1, after: after) }
        ids = response.ids
        more = ids.size > limit
        ids = ids.first(limit)
        entries = Entry.where(id: ids).for_api_v3.index_by(&:id)
        after = more ? sort_values(response, limit) : nil
        [ids.filter_map { entries[_1] }, after, response.total]
      end

      private

      def index
        Search.index_name(Entry.table_name)
      end

      # The id tiebreak keeps search_after from skipping or repeating hits.
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
        # Unescaped colons would end the range token early.
        parts << "published:>#{@published_after.utc.iso8601.gsub(":", "\\:")}" if @published_after
        text = (parts.any? && @text.match?(/\bOR\b/)) ? "(#{@text})" : @text
        [text, *parts].reject(&:empty?).join(" ")
      end

      # The limit-th hit's sort values; the search fetched one extra to detect more.
      def sort_values(response, limit)
        hits = response.data.safe_dig("hits", "hits")
        hits[limit - 1]["sort"]
      end
    end
  end
end
