class AddEntryCreatedAtToUnreadEntries < ActiveRecord::Migration
  def change
    add_column :unread_entries, :entry_created_at, :datetime
    add_index :unread_entries, :entry_created_at
  end
end
