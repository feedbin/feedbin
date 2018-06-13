class RemoveCreatedAtIndexFromEntries < ActiveRecord::Migration[4.2]
  def change
    remove_index :entries, :created_at
  end
end
