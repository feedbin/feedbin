module Api
  module V3
    module Collections
      # GET /collections/{id}/ids: the whole id list, with an ETag that
      # answers a quiet poll without loading it. The timeline has none.
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
