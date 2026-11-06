module Api
  module V3
    class SearchController < ApiController
      include SearchPage

      def index
        query = params[:query].to_s
        raise invalid_param(:query, "missing", "query is required.") if query.strip.empty?
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
