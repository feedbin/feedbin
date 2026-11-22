module Api
  module V3
    module ShareServiceScoped
      extend ActiveSupport::Concern

      private

      # The supported service, by its id (`pinboard`), and the user's setup of it, if any.
      def set_share_service
        @info = ShareServiceCatalog.info!(params[:share_service_id] || params[:id])
        @record = @user.supported_sharing_services.find_by(service_id: @info.service_id)
      end

      def render_share_service(status: :ok)
        render json: ShareServiceSerializer.new(@info, @record).to_h, status: status
      end
    end
  end
end
