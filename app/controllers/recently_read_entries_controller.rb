class RecentlyReadEntriesController < ApplicationController
  def index
    @user = current_user
    update_selected_feed!("collection_recently_read")

    recently_read_entry_ids = @user.recently_read_entries.order(id: :desc).limit(100).pluck(:entry_id)
    @entries = Entry.where(id: recently_read_entry_ids).includes(feed: [:favicon]).entries_list
    @entries = @entries.sort_by { |entry| recently_read_entry_ids.index(entry.id) }

    @type = "recently_read"
    @collection_title = "Recently Read"

    respond_to do |format|
      format.js { render partial: "shared/entries" }
    end
  end

  def settings

  end

  def create
    @user = current_user
    RecentlyReadEntry.create(user: @user, entry_id: params[:id])
    head :ok
  end

  def destroy_all
    @user = current_user
    @user.recently_read_entries.delete_all
  end
end
