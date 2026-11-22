module Api
  module V3
    class ShareServicesController < ApiController
      include ShareServiceScoped

      before_action :set_share_service, only: [:update, :destroy]

      def index
        data = ShareServiceCatalog.new(@user).services
        return unless stale?(etag: digest(data))
        render_list(data)
      end

      # Turns the service on, or changes its setup.
      def update
        @record = ShareServiceSetup.new(@user, @info, body).apply
        render_share_service
      rescue ShareServiceSetup::TokenRefused => error
        render_problem :unprocessable_content, "token_invalid", title: "Token invalid", detail: error.message
      end

      def destroy
        @record&.destroy
        head :no_content
      end
    end
  end
end
