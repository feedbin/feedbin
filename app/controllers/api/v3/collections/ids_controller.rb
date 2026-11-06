module Api
  module V3
    module Collections
      class IdsController < ApiController
        include CollectionScoped

        def show
          return status_not_found if @collection.timeline?
          return if not_modified?(etag_for(@collection.id, @collection.ids_version))
          render_list(@collection.ids)
        end
      end
    end
  end
end
