class AddStarredEntriesCountIndexToEntries < ActiveRecord::Migration
  disable_ddl_transaction!

  def change
    add_index :entries, :starred_entries_count, algorithm: :concurrently
  end
end
