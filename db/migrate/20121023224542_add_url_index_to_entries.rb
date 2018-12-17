class AddUrlIndexToEntries < ActiveRecord::Migration[4.2]
  def up
    add_index :entries, :url
  end

  def down
    remove_index :entries, :url
  end
end
