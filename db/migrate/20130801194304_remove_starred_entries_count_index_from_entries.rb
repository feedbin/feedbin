class RemoveStarredEntriesCountIndexFromEntries < ActiveRecord::Migration[4.2]
  def change
    remove_index :entries, :starred_entries_count
  end
end
