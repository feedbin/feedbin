class RecentlyPlayedEntriesController < ApplicationController
  def index
    @user = current_user
    update_selected_feed!("collection_recently_played")

    recently_played_entries = @user.recently_played_entries.order("created_at DESC").limit(100)
    recently_played_entry_ids = []
    recently_played_entries.each { |recently_played_entry| recently_played_entry_ids << recently_played_entry.entry_id }
    @entries = Entry.where(id: recently_played_entry_ids).includes(feed: [:favicon]).entries_list
    @entries = @entries.sort_by { |entry| recently_played_entry_ids.index(entry.id) }

    @type = "recently_played"
    @collection_title = "Recently Played"

    respond_to do |format|
      format.js { render partial: "shared/entries" }
    end
  end

  def settings

  end

  def create
    @user = current_user
    if record = @user.recently_played_entries.find_or_create_by(entry_id: params[:id])
      record.update(recently_played_entry_params)
    end
    head :ok
  end

  def destroy_all
    @user = current_user
    @user.recently_played_entries.delete_all
  end

  private

  def recently_played_entry_params
    params.require(:recently_played_entry).permit(:progress, :duration)
  end
end
