class CreateRecentlyReadEntries < ActiveRecord::Migration[4.2]
  def change
    create_table :recently_read_entries do |t|
      t.references :user, index: true
      t.references :entry

      t.timestamps
    end
    add_index :recently_read_entries, [:user_id, :entry_id], unique: true
    add_index :recently_read_entries, [:created_at]
  end
end
