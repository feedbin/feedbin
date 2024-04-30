class Settings::NewslettersController < ApplicationController
  layout "settings"

  def show
    render Settings::Newsletters::IndexView.new(user: current_user, subscription_ids: @user.subscriptions.pluck(:feed_id))
  end
end
