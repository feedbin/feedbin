class RemoveEntryIdFromEntries < ActiveRecord::Migration
  def up
    remove_index :entries, :entry_id
    remove_column :entries, :entry_id
  end

  def down
    add_column :entries, :entry_id, :string
    add_index :entries, :entry_id
  end


end
