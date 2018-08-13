class AddIndexesToEntryStates < ActiveRecord::Migration[4.2]
  def up
    add_index :entry_states, :read
    add_index :entry_states, :starred
    add_index :entry_states, [:user_id, :starred]
    add_index :entry_states, [:user_id, :read]
  end

  def down
    remove_index :entry_states, :read
    remove_index :entry_states, :starred
    remove_index :entry_states, [:user_id, :starred]
    remove_index :entry_states, [:user_id, :read]
  end
end
