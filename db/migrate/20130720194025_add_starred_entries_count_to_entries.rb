class AddStarredEntriesCountToEntries < ActiveRecord::Migration
  def change
    add_column :entries, :starred_entries_count, :integer, null: false, default: 0
  end
end
