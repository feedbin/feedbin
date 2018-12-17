class IndexUnreadEntriesOnUserIdAndCreatedAt < ActiveRecord::Migration[4.2]
  disable_ddl_transaction!

  def change
    add_index :unread_entries, [:user_id, :created_at], algorithm: :concurrently
  end
end
