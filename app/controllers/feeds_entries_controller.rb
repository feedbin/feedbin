class FeedsEntriesController < ApplicationController

  before_action :correct_user
  etag { current_user.try :id }

  def index
    @user = current_user
    update_selected_feed!("feed", params[:feed_id])

    @feed_ids = params[:feed_id]
    feeds_response

    @append = !params[:page].nil?

    # Extra data for updating buttons
    @feed = @user.feed_with_subscription_id(params[:feed_id])
    @tags = @user.tags.where(taggings: {feed_id: @feed}).pluck(:name).sort
    @type = 'feed'
    @data = params[:feed_id]

    respond_to do |format|
      format.js { render partial: 'shared/entries' }
    end
  end

  private

  def correct_user
    unless current_user.subscribed_to?(params[:feed_id])
      render_404
    end
  end


end
