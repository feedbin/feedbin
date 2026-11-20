module Api
  module V3
    # The user's own share links: a name and an address with `${url}` and `${title}` in it, which the app opens.
    class CustomShareServicesController < ApiController
      include BodyFields

      before_action :set_custom_share_service, only: [:update, :destroy]

      def index
        data = @user.sharing_services.map { CustomShareServiceSerializer.new(_1).to_h }
        return unless stale?(etag: digest(data))
        render_list(data)
      end

      def create
        service = @user.sharing_services.create!(label: required_string("label"), url: required_string("url"))
        render json: CustomShareServiceSerializer.new(service).to_h, status: :created
      end

      def update
        @service.label = required_string("label") if body.key?("label")
        @service.url = required_string("url") if body.key?("url")
        @service.save!
        render json: CustomShareServiceSerializer.new(@service).to_h
      end

      def destroy
        @service.destroy
        head :no_content
      end

      private

      def set_custom_share_service
        @service = @user.sharing_services.find(params[:id])
      end
    end
  end
end
