class CreateStarredEntries < ActiveRecord::Migration[4.2]
  def change
    create_table :starred_entries do |t|
      t.references :user, index: true
      t.references :feed, index: true
      t.references :entry, index: true
      t.datetime :published

      t.timestamps
    end
    add_index :starred_entries, :published
    add_index :starred_entries, [:user_id, :entry_id], unique: true
  end
end
