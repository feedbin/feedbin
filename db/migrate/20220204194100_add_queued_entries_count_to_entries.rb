class AddQueuedEntriesCountToEntries < ActiveRecord::Migration[7.0]
  def change
    add_column :entries, :queued_entries_count, :bigint, default: 0, null: false
  end
end
