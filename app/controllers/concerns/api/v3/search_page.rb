# Renders one page of an EntrySearch as an entries list: the envelope, the
# search cursor (the last hit's sort values), and meta.query. Shared by
# GET /search, a saved search's collection entries, and an action preview.
module Api
  module V3
    module SearchPage
      extend ActiveSupport::Concern

      private

      def render_search_page(search, total: false)
        limit = page_limit(default: EntrySearch::DEFAULT_LIMIT, max: EntrySearch::MAX_LIMIT)
        after = search_cursor
        entries, next_after, count = search.page(limit: limit, after: after)
        next_cursor = next_after && Cursor.encode(sort: EntrySearch::CURSOR_SORT, after: next_after)
        meta = {as_of: as_of, query: search.expanded_query}
        meta[:total] = count if total
        render_list(
          serialize_entries(entries),
          page: page_object(limit: limit, next_cursor: next_cursor, more: !next_cursor.nil?),
          meta: meta
        )
      end

      def search_cursor
        fields = cursor_fields or return nil
        raise Cursor::Invalid unless fields["sort"] == EntrySearch::CURSOR_SORT && fields["after"].is_a?(Array) && fields["after"].any?
        fields["after"]
      end
    end
  end
end
