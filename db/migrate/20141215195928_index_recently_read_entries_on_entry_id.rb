class IndexRecentlyReadEntriesOnEntryId < ActiveRecord::Migration
  disable_ddl_transaction!
  def change
    add_index :recently_read_entries, :entry_id, algorithm: :concurrently
  end
end
