class RemoveStarredEntriesCountIndexFromEntries < ActiveRecord::Migration
  def change
    remove_index :entries, :starred_entries_count
  end
end
