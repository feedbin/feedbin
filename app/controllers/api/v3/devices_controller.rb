module Api
  module V3
    class DevicesController < ApiController
      before_action -> { doorkeeper_authorize! :account }

      def create
        device, created = DeviceRegistration.new(@user, body).register
        render json: DeviceSerializer.new(device).to_h, status: created ? :created : :ok
      end

      def destroy
        @user.devices.find(params[:id]).destroy
        head :no_content
      end
    end
  end
end
