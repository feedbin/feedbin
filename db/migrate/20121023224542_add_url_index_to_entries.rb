class AddUrlIndexToEntries < ActiveRecord::Migration
  def up
    add_index :entries, :url
  end
  def down
    remove_index :entries, :url
  end
end
