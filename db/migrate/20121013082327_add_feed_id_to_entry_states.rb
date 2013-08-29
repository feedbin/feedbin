class AddFeedIdToEntryStates < ActiveRecord::Migration
  def up
    add_column :entry_states, :feed_id, :integer
    add_index :entry_states, :feed_id
  end

  def down
    remove_column :entry_states, :feed_id
  end
end
