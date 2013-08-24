class DropEntryStates < ActiveRecord::Migration
  def up
    drop_table :entry_states
  end
  def down; end
end
