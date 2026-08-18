class PagesEntriesController < ApplicationController
  def index
    @user = current_user

    @feed = @user.feeds.find(params[:id])
    @append = params[:page].present?
    view_mode = params[:view] || params[:view_mode]

    if view_mode == "view_all"
      @entries = pagination_anchor(@feed.entries, column: Entry.arel_table[:id]).page(params[:page]).order("created_at DESC").entries_list
      @page_query = @entries
    elsif view_mode == "view_starred"
      # Display in the order the pagination cut: starred_entries.created_at
      # (when starred), not entries.created_at (when ingested), or entries
      # jump across page boundaries.
      starred_entries = pagination_anchor(@user.starred_entries.select(:entry_id, :created_at).where(feed_id: @feed.id)).page(params[:page]).order("created_at DESC")
      entry_ids = starred_entries.map(&:entry_id)
      @entries = Entry.in_order_of(:id, entry_ids).where(id: entry_ids).entries_list
      @page_query = starred_entries
    else
      @all_unread = "true"
      unread_entries = pagination_anchor(@user.unread_entries.select(:entry_id).where(feed_id: @feed.id)).page(params[:page]).order("entry_created_at DESC")
      @entries = Entry.where(id: unread_entries).order("created_at DESC").entries_list
      @page_query = unread_entries
    end

    render partial: "shared/entries"
  end
end
