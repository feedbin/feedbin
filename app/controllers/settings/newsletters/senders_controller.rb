class Settings::Newsletters::SendersController < ApplicationController
  layout "settings"

  def index
    feed_ids = @user.subscriptions.pluck(:feed_id)

    @senders = if params[:q].present?
      search_senders
    end

    @feed_ids = @user.subscriptions.pluck(:feed_id)

    respond_to do |format|
      format.html do
        render Settings::Newsletters::Senders::IndexView.new(user: current_user, feed_ids: @feed_ids, senders: @senders)
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

  private

  def search_senders
    query = params[:q]
    tokens = if query.include?("to:")
      query = query.delete_prefix("to:").split("@").first.strip
      @user.newsletter_addresses.where(token: query).pluck(:token)
    else
      @user.newsletter_addresses.pluck(:token)
    end
    NewsletterSender.where(token: tokens).select { |sender|
      sender.search_data.include?(query.to_s.downcase.gsub(/\s+/, ""))
    }
  end

end
