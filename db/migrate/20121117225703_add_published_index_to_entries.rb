class AddPublishedIndexToEntries < ActiveRecord::Migration[4.2]
  def up
    add_index :entries, :published
  end

  def down
    remove_index :entries, :published
  end
end
