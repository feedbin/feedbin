class CreateRecentlyPlayedEntries < ActiveRecord::Migration[5.0]
  def change
    create_table :recently_played_entries do |t|
      t.references :user, foreign_key: false, null: false, index: true
      t.references :entry, foreign_key: false, null: false
      t.integer :progress, null: false, default: 0
      t.integer :duration, null: false, default: 0

      t.timestamps
    end

    add_index :recently_played_entries, [:user_id, :entry_id], unique: true
    add_index :recently_played_entries, [:user_id, :created_at]
  end
end
