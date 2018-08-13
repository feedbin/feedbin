class AddFeedIdToEntryStates < ActiveRecord::Migration[4.2]
  def up
    add_column :entry_states, :feed_id, :integer
    add_index :entry_states, :feed_id

    EntryState.find_each do |entry_state|
      entry_state.feed_id = entry_state.entry.feed_id
      entry_state.save!
    end
  end

  def down
    remove_column :entry_states, :feed_id
  end
end
