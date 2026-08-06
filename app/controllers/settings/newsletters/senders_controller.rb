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

    head :not_found and return unless sender

    Subscription.set_subscribed(@user, sender.feed_id, params[:newsletter_sender][:active] == "1")

    flash[:notice] = "Settings updated."
    flash.discard
  end

  private

  def search_senders
    query = params[:q].to_s
    # start_with?, not include?: a sender whose own name contains "to:" was
    # taking the prefix branch and being searched for as an address.
    tokens = if query.start_with?("to:")
      # "to:" on its own is what the field holds between typing the prefix and
      # typing the address, and split("@") on the empty string is [], not [""].
      # An address that is not there yet narrows nothing.
      query = query.delete_prefix("to:").split("@").first.to_s.strip
      if query.empty?
        @user.newsletter_addresses.pluck(:token)
      else
        @user.newsletter_addresses.where(token: query).pluck(:token)
      end
    else
      @user.newsletter_addresses.pluck(:token)
    end
    NewsletterSender.where(token: tokens).select { |sender|
      sender.search_data.include?(query.to_s.downcase.gsub(/\s+/, ""))
    }
  end

end
