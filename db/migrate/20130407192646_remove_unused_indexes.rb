class RemoveUnusedIndexes < ActiveRecord::Migration[4.2]
  def change
    remove_index :entry_states, :starred
    remove_index :entry_states, :read
    remove_index :taggings, :feed_id
    remove_index :billing_events, :event_type
    remove_index :entries, :published
  end
end
