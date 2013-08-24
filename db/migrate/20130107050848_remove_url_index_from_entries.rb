class RemoveUrlIndexFromEntries < ActiveRecord::Migration
  def up
    remove_index :entries, :url
  end

  def down
    add_index :entries, :url
  end
end
