class RemoveEntryIdFromEntries < ActiveRecord::Migration[4.2]
  def up
    remove_index :entries, name: :index_entries_on_feed_id_and_entry_id
    remove_index :entries, :entry_id
    remove_column :entries, :entry_id
  end

  def down
    add_column :entries, :entry_id, :string
    add_index :entries, :entry_id
    add_index :entries, [:feed_id, :entry_id], unique: true
  end
end
