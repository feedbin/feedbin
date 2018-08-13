class UpdatedEntriesController < ApplicationController
  def index
    @user = current_user
    update_selected_feed!("collection_updated")

    updated_entry_ids = @user.updated_entries.order(updated_at: :desc).limit(100).pluck(:entry_id)
    @entries = Entry.where(id: updated_entry_ids).includes(feed: [:favicon])
    @entries = @entries.sort_by { |entry| updated_entry_ids.index(entry.id) }

    @type = "updated"
    @collection_title = "Updated"
    @force_preload = true

    respond_to do |format|
      format.js { render partial: "shared/entries" }
    end
  end
end
