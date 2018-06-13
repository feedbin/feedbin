class RemoveEntryCreatedAtIndexFromUnreadEntries < ActiveRecord::Migration[4.2]
  def change
    remove_index :unread_entries, :entry_created_at
  end
end
