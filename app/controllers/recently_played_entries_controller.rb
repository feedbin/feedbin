class RecentlyPlayedEntriesController < ApplicationController
  def index
    @user = current_user

    recently_played_entries = @user.recently_played_entries.order("created_at DESC").limit(100)
    recently_played_entry_ids = []
    recently_played_entries.each { |recently_played_entry| recently_played_entry_ids << recently_played_entry.entry_id }
    @entries = Entry.where(id: recently_played_entry_ids).includes(feed: [:favicon]).entries_list
    @entries = @entries.sort_by { |entry| recently_played_entry_ids.index(entry.id) }

    @collection_title = "Recently Played"

    respond_to do |format|
      format.js { render partial: "shared/entries" }
    end
  end

  def settings
  end

  def create
    @user = current_user
    if @user.can_read_entry?(params[:id])
      if queued = @user.queued_entries.find_by(entry_id: params[:id])
        queued.update(recently_played_entry_params)
      end
      if recent = @user.recently_played_entries.find_by(entry_id: params[:id])
        recent.update(recently_played_entry_params)
      end
      if !recent && !queued
        recent = @user.recently_played_entries.find_or_create_by(entry_id: params[:id])
        recent.update(recently_played_entry_params)
      end
    end
    head :ok
  end

  def destroy_all
    @user = current_user
    @user.recently_played_entries.delete_all
  end

  def progress
    @user = current_user
    render json: @user.recently_played_entries_progress.to_json
  end

  private

  def recently_played_entry_params
    params.require(:recently_played_entry).permit(:progress, :duration)
  end

  def queued_entry_params
    params.require(:recently_played_entry).permit(:progress, :duration)
  end
end
