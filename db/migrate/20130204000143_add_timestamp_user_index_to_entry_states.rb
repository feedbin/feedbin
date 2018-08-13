class AddTimestampUserIndexToEntryStates < ActiveRecord::Migration[4.2]
  def change
    add_index :entry_states, [:user_id, :read_updated_at, :starred_updated_at], name: "index_entry_states_on_user_and_state_timestamps"
  end
end
