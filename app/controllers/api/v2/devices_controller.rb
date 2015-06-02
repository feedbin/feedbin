module Api
  module V2
    class DevicesController < ApiController

      respond_to :json

      before_action :validate_content_type, only: [:create]

      def create
        @user = current_user
        Device.where("lower(token) = ?", params[:device][:token].downcase).destroy_all
        token = params[:device][:old_token] || params[:device][:token]
        @user.devices.where("lower(token) = ?", token.downcase).first_or_create.update_attributes(device_params)
        render nothing: true
      end

      def test
        @user = current_user
        subscription = @user.subscriptions.order("RANDOM()").limit(1).first
        entry = Entry.where(feed_id: subscription.feed_id).order("RANDOM()").limit(1).first
        DevicePushNotificationSend.perform_async([@user.id], entry.id)
        render nothing: true
      end

      private

      def device_params
        params.require(:device).permit(:token, :device_type, :model, :application, :operating_system)
      end

    end
  end
end
