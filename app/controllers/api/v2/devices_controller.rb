module Api
  module V2
    class DevicesController < ApiController
      respond_to :json

      before_action :validate_content_type, only: [:create]
      skip_before_action :valid_user

      def create
        @user = current_user
        Device.register(@user, device_params[:token], device_params)
        head :ok
      end

      def ios_test
        @user = current_user
        subscription = @user.subscriptions.order(Arel.sql("RANDOM()")).limit(1).first
        entry = Entry.where(feed_id: subscription.feed_id).order(Arel.sql("RANDOM()")).limit(1).first
        DevicePushNotificationSend.perform_async([@user.id], entry.id, false)
        head :ok
      end

      def safari_test
        @user = current_user
        subscription = @user.subscriptions.order(Arel.sql("RANDOM()")).limit(1).first
        entry = Entry.where(feed_id: subscription.feed_id).order(Arel.sql("RANDOM()")).limit(1).first
        WebPushNotificationSend.perform_async([@user.id], entry.id, false)
        head :ok
      end

      private

      def device_params
        params.require(:device).permit(:token, :device_type, :model, :application, :operating_system, :active)
      end
    end
  end
end
