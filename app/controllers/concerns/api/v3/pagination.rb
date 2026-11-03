# The list envelope and cursor pagination from conventions.md: every list is
# { object: "list", data:, page:, meta: }, and a page ends with a null
# next_cursor.
module Api
  module V3
    module Pagination
      extend ActiveSupport::Concern

      DEFAULT_LIMIT = 1_000
      MAX_LIMIT = 1_000

      included do
        rescue_from Cursor::Invalid do
          render_problem :bad_request, "cursor_invalid",
            title: "Invalid cursor",
            detail: "The cursor could not be decoded. Restart from the first page."
        end
      end

      private

      # meta is present only on lists that carry one: entries lists, whose
      # as_of is the time bound a client bootstraps its cursors from. A list
      # that needs no cursor (ids, subscriptions, feeds, tokens) has none.
      def render_list(data, page: nil, meta: nil)
        body = {object: "list", data: data}
        body[:page] = page if page
        body[:meta] = meta if meta
        render json: body
      end

      # next_url is the page to follow now and is null at the end. next_cursor
      # is where to resume; for a sort that follows arrivals it outlives
      # next_url (more: false), so the two are passed separately.
      def page_object(limit:, next_cursor:, more: next_cursor.present?)
        {
          limit: limit,
          next_cursor: next_cursor,
          next_url: more ? next_page_url(next_cursor) : nil
        }
      end

      # This request with cursor replaced, ready for the client to follow.
      def next_page_url(cursor)
        uri = URI(request.url)
        uri.query = request.query_parameters.merge("cursor" => cursor).to_query
        uri.to_s
      end

      def page_limit(default: DEFAULT_LIMIT, max: MAX_LIMIT)
        return default unless params.key?(:limit)
        limit = Integer(params[:limit], exception: false)
        raise invalid_param(:limit, "out_of_range", "limit must be an integer from 1 to #{max}.") unless limit&.between?(1, max)
        limit
      end

      def cursor_fields
        params[:cursor].present? ? Cursor.decode(params[:cursor]) : nil
      end

      def as_of
        @as_of ||= Time.now.utc.iso8601
      end
    end
  end
end
