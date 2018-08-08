class RemoveRecentlyPlayedEntriesCountIndexFromEntries < ActiveRecord::Migration[5.1]
  disable_ddl_transaction!

  def up
    remove_index :entries, :recently_played_entries_count
  end

  def down
    add_index :entries, :recently_played_entries_count, algorithm: :concurrently
  end
end
