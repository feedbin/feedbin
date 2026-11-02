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

      private

      def id_list(name)
        return nil unless params.key?(name)
        ids = params[name].to_s.split(",").map { Integer(_1.strip, exception: false) }
        raise Problems::InvalidParameter.new("#{name} must be comma-separated ids.", pointer: name.to_s, code: "invalid_value") if ids.empty? || ids.any?(&:nil?)
        ids
      end

      def boolean_param(name)
        return nil unless params.key?(name)
        case params[name]
        when "true" then true
        when "false" then false
        else raise Problems::InvalidParameter.new("#{name} must be true or false.", pointer: name.to_s, code: "invalid_value")
        end
      end

      def time_param(name)
        return nil unless params.key?(name)
        Time.iso8601(params[name].to_s)
      rescue ArgumentError
        raise Problems::InvalidParameter.new("#{name} must be an RFC 3339 timestamp.", pointer: name.to_s, code: "invalid_value")
      end
    end
  end
end
