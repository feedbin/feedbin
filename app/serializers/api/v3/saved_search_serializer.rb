module Api
  module V3
    # The saved search object. Its results are read through the collection
    # search_{id}.
    class SavedSearchSerializer
      def initialize(saved_search)
        @saved_search = saved_search
      end

      def to_h
        {
          object: "saved_search",
          id: @saved_search.id,
          title: @saved_search.name,
          query: @saved_search.query,
          collection_id: "search_#{@saved_search.id}",
          created_at: @saved_search.created_at.utc.iso8601,
          updated_at: @saved_search.updated_at.utc.iso8601
        }
      end
    end
  end
end
