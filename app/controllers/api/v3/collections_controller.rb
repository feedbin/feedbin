module Api
  module V3
    class CollectionsController < ApiController
      def index
        data = Collection.all(@user).map(&:to_h)
        return unless stale?(etag: digest(data))
        render_list(data)
      end
    end
  end
end
