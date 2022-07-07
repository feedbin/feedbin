class QueuedEntriesController < ApplicationController
  def index
    @user = current_user

    queued_entry_ids = @user.queued_entries.order(order: :asc).pluck(:entry_id)
    @entries = Entry.where(id: queued_entry_ids).includes(feed: [:favicon]).entries_list
    @entries = @entries.sort_by { |entry| queued_entry_ids.index(entry.id) }

    @type = "queued_entries"
    @collection_title = "Queued Entries"
    @entry_class = "always-unread"

    respond_to do |format|
      format.js { render partial: "shared/entries" }
    end
  end
end
