class Settings::Newsletters::SendersController < ApplicationController
  layout "settings"

  def index
    respond_to do |format|
      format.html do
        render Settings::Newsletters::Senders::IndexView.new(user: current_user, params:)
      end
      format.js {}
    end
  end

  def update
    sender = @user.authentication_tokens.find_by_token(params[:newsletter_sender][:token])&.newsletter_senders&.find(params[:id])

    if params[:newsletter_sender][:active] == "1"
      @user.subscriptions.create!(feed_id: sender.feed_id)
    else
      @user.subscriptions.where(feed_id: sender.feed_id).take.destroy
    end

    flash[:notice] = "Settings updated."
    flash.discard
  end

end
