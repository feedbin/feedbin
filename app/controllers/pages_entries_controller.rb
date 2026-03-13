class PagesEntriesController < ApplicationController
  def index
    @user = current_user
    pagination_anchor

    @feed = @user.feeds.find(params[:id])
    @append = params[:page].present?
    view_mode = params[:view] || params[:view_mode]

    if view_mode == "view_all"
      scope = @feed.entries
      scope = scope.where("entries.id <= ?", @anchor) if @anchor
      @entries = scope.includes(feed: [:favicon]).page(params[:page]).order("created_at DESC").entries_list
      @page_query = @entries
    elsif view_mode == "view_starred"
      scope = @user.starred_entries.select(:entry_id).where(feed_id: @feed.id)
      scope = scope.where("entry_id <= ?", @anchor) if @anchor
      starred_entries = scope.page(params[:page]).order("created_at DESC")
      @entries = Entry.where(id: starred_entries).includes(feed: [:favicon]).order("created_at DESC").entries_list
      @page_query = starred_entries
    else
      @all_unread = "true"
      scope = @user.unread_entries.select(:entry_id).where(feed_id: @feed.id)
      scope = scope.where("entry_id <= ?", @anchor) if @anchor
      unread_entries = scope.page(params[:page]).order("entry_created_at DESC")
      @entries = Entry.where(id: unread_entries).includes(feed: [:favicon]).order("created_at DESC").entries_list
      @page_query = unread_entries
    end

    render partial: "shared/entries"
  end
end
