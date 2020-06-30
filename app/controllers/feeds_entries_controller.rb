class FeedsEntriesController < ApplicationController
  before_action :check_user

  etag { current_user.try :id }

  def index
    @user = current_user

    @feed_ids = params[:feed_id]
    feeds_response

    @append = params[:page].present?

    # Extra data for updating buttons
    @subscription = @user.subscriptions.where(feed_id: params[:feed_id]).take!
    @feed = @subscription.feed
    respond_to do |format|
      format.js { render partial: "shared/entries" }
    end
  end

  private

  def check_user
    unless current_user.subscribed_to?(params[:feed_id])
      render_404
    end
  end
end
