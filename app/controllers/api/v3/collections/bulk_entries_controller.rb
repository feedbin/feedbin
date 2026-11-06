module Api
  module V3
    module Collections
      class BulkEntriesController < ApiController
        include CollectionScoped

        before_action -> { ensure_collection_accepts("update") }, only: :update
        before_action -> { ensure_collection_accepts("clear") }, only: :destroy

        def update
          render json: @collection.update_entries(body["entries"])
        end

        def destroy
          @collection.clear
          head :no_content
        end
      end
    end
  end
end
