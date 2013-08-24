class AddIndexToTimestamps < ActiveRecord::Migration
  def change
    add_index :entry_states, :updated_at
    add_index :entries, :created_at
    add_index :subscriptions, :created_at
  end
end
