module Api
  module V3
    class CollectionsController < ApiController
      def index
        data = Collection.all(@user).map(&:to_h)
        return if not_modified?(etag_for("collections", digest(data)))
        render_list(data)
      end
    end
  end
end
