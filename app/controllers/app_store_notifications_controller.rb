class AppStoreNotificationsController < ApplicationController
  def show
    @user = current_user
    @billing_event = @user.app_store_notifications.find(params[:id])
    render layout: false
  end
end
