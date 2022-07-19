class AddFeedIdIndexToEntries < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  NAME = "index_entries_on_feed_id_include_id_published_created_at"
  def up
    execute "CREATE INDEX CONCURRENTLY #{NAME} ON entries (feed_id) INCLUDE (id, published, created_at)"
  end
  def down
    remove_index :entries, NAME
  end
end
