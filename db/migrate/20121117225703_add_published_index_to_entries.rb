class AddPublishedIndexToEntries < ActiveRecord::Migration
  def up
    add_index :entries, :published
  end
  def down
    remove_index :entries, :published
  end
end
