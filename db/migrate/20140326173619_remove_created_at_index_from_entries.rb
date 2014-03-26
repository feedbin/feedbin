class RemoveCreatedAtIndexFromEntries < ActiveRecord::Migration
  def change
    remove_index :entries, :created_at
  end
end
