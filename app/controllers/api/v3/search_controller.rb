module Api
  module V3
    # GET /search: full-text search with the structured parameters folded
    # into the query, paged by cursor with no depth limit.
    class SearchController < ApiController
      include SearchPage

      def index
        query = params[:query].to_s
        raise Problems::InvalidParameter.new("query is required.", pointer: "query", code: "missing") if query.strip.empty?
        search = EntrySearch.new(@user,
          query: query,
          feed_ids: id_list(:feed_ids),
          tag_ids: id_list(:tag_ids),
          read: boolean_param(:read),
          starred: boolean_param(:starred),
          published_after: time_param(:published_after))
        render_search_page(search, total: boolean_param(:total) == true)
      end
    end
  end
end
