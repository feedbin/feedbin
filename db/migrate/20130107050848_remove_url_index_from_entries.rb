class RemoveUrlIndexFromEntries < ActiveRecord::Migration[4.2]
  def up
    remove_index :entries, :url
  end

  def down
    add_index :entries, :url
  end
end
