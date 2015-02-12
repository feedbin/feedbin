class RecentlyReadEntriesController < ApplicationController

  def index
    @user = current_user
    update_selected_feed!("collection_recently_read")

    recently_read_entries = @user.recently_read_entries.order('created_at DESC').limit(100)
    recently_read_entry_ids = []
    recently_read_entries.each {|recently_read_entry| recently_read_entry_ids << recently_read_entry.entry_id}
    @entries = Entry.where(id: recently_read_entry_ids).includes(:feed).entries_list
    @entries = @entries.sort_by{ |entry| recently_read_entry_ids.index(entry.id) }

    @type = 'recently_read'

    @collection_title = 'Recently Read'

    respond_to do |format|
      format.js { render partial: 'shared/entries' }
    end
  end

  def create
    @user = current_user
    RecentlyReadEntry.create(user: @user, entry_id: params[:id])
    render nothing: true
  end

end
