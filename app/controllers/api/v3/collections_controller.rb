module Api
  module V3
    # The sidebar's collections. Each one's ids, entries and membership
    # writes are under Collections::.
    class CollectionsController < ApiController
      def index
        data = Collection.all(@user).map(&:to_h)
        return if not_modified?(etag_for("collections", digest(data)))
        render_list(data)
      end
    end
  end
end
