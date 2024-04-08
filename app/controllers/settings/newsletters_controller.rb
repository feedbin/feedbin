class Settings::NewslettersController < ApplicationController
  layout "settings"

  def show
    user = current_user
    if user.setting_on?(:addresses_available)
      render Settings::Newsletters::IndexView.new(user: current_user, subscription_ids: @user.subscriptions.pluck(:feed_id))
    else
      render Settings::NewslettersPagesView.new(user: current_user, subscription_ids: @user.subscriptions.pluck(:feed_id))
    end
  end
end
