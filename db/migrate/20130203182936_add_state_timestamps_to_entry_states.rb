class AddStateTimestampsToEntryStates < ActiveRecord::Migration[4.2]
  def change
    add_column :entry_states, :starred_at, :datetime
    add_column :entry_states, :read_at, :datetime

    add_column :entry_states, :starred_updated_at, :datetime
    add_column :entry_states, :read_updated_at, :datetime

    add_index :entry_states, :starred_updated_at
    add_index :entry_states, :read_updated_at
  end
end
