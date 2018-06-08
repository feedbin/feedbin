class AddStarredEntriesCountToEntries < ActiveRecord::Migration[4.2]
  def change
    add_column :entries, :starred_entries_count, :integer, null: false, default: 0
  end
end
