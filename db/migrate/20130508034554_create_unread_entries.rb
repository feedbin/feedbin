class CreateUnreadEntries < ActiveRecord::Migration[4.2]
  def change
    create_table :unread_entries do |t|
      t.references :user, index: true
      t.references :feed, index: true
      t.references :entry, index: true
      t.datetime :published

      t.timestamps
    end

    add_index :unread_entries, [:user_id, :feed_id, :published]
    add_index :unread_entries, [:user_id, :published]
    add_index :unread_entries, [:user_id, :entry_id], unique: true
  end
end
