# The list envelope and cursor pagination from conventions.md: every list is
# { object: "list", data:, page:, meta: }, and a page ends with a null
# next_cursor.
module Api
  module V3
    module Pagination
      extend ActiveSupport::Concern

      DEFAULT_LIMIT = 100
      MAX_LIMIT = 1_000

      included do
        rescue_from Cursor::Invalid do
          render_problem :bad_request, "cursor_invalid",
            title: "Invalid cursor",
            detail: "The cursor could not be decoded. Restart from the first page."
        end
      end

      private

      def render_list(data, page: nil, meta: {})
        body = {object: "list", data: data}
        body[:page] = page if page
        body[:meta] = {as_of: as_of}.merge(meta)
        render json: body
      end

      def page_object(limit:, next_cursor:)
        {
          limit: limit,
          next_cursor: next_cursor,
          next_url: next_cursor && next_page_url(next_cursor)
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
        raise Problems::InvalidParameter.new("limit must be an integer from 1 to #{max}.", pointer: "limit", code: "out_of_range") unless limit&.between?(1, max)
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
