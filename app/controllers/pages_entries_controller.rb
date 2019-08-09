class PagesEntriesController < ApplicationController

  def index
    @user = current_user

    @feed = @user.feeds.find(params[:id])
    @append = params[:page].present?

    if helpers.view_mode == "view_all"
      @entries = @feed.entries.includes(feed: [:favicon]).page(params[:page]).order("created_at DESC").entries_list
      @page_query = @entries
    elsif helpers.view_mode == "view_starred"
      starred_entries = @user.starred_entries.select(:entry_id).where(feed_id: @feed.id).page(params[:page]).order("created_at DESC")
      @entries = Entry.entries_with_feed(starred_entries, "DESC").entries_list
      @page_query = starred_entries
    else
      @all_unread = "true"
      unread_entries = @user.unread_entries.select(:entry_id).where(feed_id: @feed.id).page(params[:page]).order("created_at DESC")
      @entries = Entry.entries_with_feed(unread_entries, @user.entry_sort).entries_list
      @page_query = unread_entries
    end

    update_selected_feed!("feed", @feed.id)

    render partial: "shared/entries"
  end

end
