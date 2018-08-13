class CreateEntryStates < ActiveRecord::Migration[4.2]
  def change
    create_table :entry_states do |t|
      t.integer :user_id
      t.integer :entry_id
      t.boolean :read, default: false
      t.boolean :starred, default: false

      t.timestamps
    end

    add_index :entry_states, :user_id
    add_index :entry_states, :entry_id
    add_index :entry_states, [:user_id, :entry_id], unique: true
  end
end
