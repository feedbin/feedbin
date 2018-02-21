class IndexRecentlyReadEntriesEntriesOnUserIdAndId < ActiveRecord::Migration[5.1]
  disable_ddl_transaction!

  def change
    add_index :recently_read_entries, [:user_id, :id], order: {user_id: :asc, id: :desc}, algorithm: :concurrently
  end
end
