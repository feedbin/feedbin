class DropEntryStates < ActiveRecord::Migration[4.2]
  def up
    drop_table :entry_states
  end

  def down
  end
end
