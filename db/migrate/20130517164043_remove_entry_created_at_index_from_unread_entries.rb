class RemoveEntryCreatedAtIndexFromUnreadEntries < ActiveRecord::Migration
  def change
    remove_index :unread_entries, :entry_created_at
  end
end
