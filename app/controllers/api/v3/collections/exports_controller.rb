module Api
  module V3
    module Collections
      # Starred articles only, as on the web: the export is built in the background and a download link emailed.
      class ExportsController < ApiController
        include CollectionScoped

        EXPORTS = 3
        EXPORT_PERIOD = 1.hour

        before_action :ensure_starred, :throttle

        def create
          StarredEntriesExport.perform_async(@user.id)
          render json: {object: "export", collection_id: @collection.id, email: @user.email}, status: :accepted
        end

        private

        def ensure_starred
          raise ActiveRecord::RecordNotFound unless @collection.id == "starred"
        end

        def throttle
          return if Throttle.throttle!("v3:starred_export:#{@user.id}", EXPORTS, EXPORT_PERIOD)
          status_rate_limited(retry_after: EXPORT_PERIOD, detail: "Too many exports. Try again in an hour.")
        end
      end
    end
  end
end
