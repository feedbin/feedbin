class FeedsController < ApplicationController

  before_action :correct_user, only: :update

  def update
    @user = current_user
    @feed = Feed.find(params[:id])
    taggings = @feed.tag(params[:feed][:tag_list], @user)

    # Open the tag drawer this was just added to
    session[:tag_visibility] ||= {}
    taggings.each do |tagging|
      session[:tag_visibility][tagging.tag_id.to_s] = true
    end

    @mark_selected = true
    get_feeds_list
    respond_to do |format|
      format.js
    end
  end

  def view_unread
    update_view_mode('view_unread')
  end

  def view_all
    # Clear the hide queue when switching to view_all incase there's anything sitting in it.
    @clear_hide_queue = true
    update_view_mode('view_all')
  end

  def auto_update
    @keep_selected = true
    if session[:view_mode] == 'view_all'
      view_all
    else
      view_unread
    end
  end

  private

  def update_view_mode(view_mode)
    @user = current_user
    @view_mode = view_mode
    session[:view_mode] = @view_mode

    @mark_selected = true
    get_feeds_list
    respond_to do |format|
      format.js { render partial: 'shared/update_view_mode' }
    end
  end

  def correct_user
    unless current_user.subscribed_to?(params[:id])
      render_404
    end
  end

end
