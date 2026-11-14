# Timeline pages and polls (/v3/entries) are keyed on (created_at, id) within
# the feeds a user subscribes to. With feed_id alone indexed, each of them
# reads every entry those feeds hold; with this, a poll is one probe per feed
# and a page reads only a window of time (Api::V3::WindowedKeysetPage).
class AddFeedIdCreatedAtIdIndexToEntries < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  NAME = "index_entries_on_feed_id_and_created_at_and_id"

  # if_not_exists: the index can be built ahead of the deploy. An interrupted
  # concurrent build leaves an INVALID index under the same name, which
  # if_not_exists would accept, so that one is dropped and built again.
  def up
    invalid = select_value(ActiveRecord::Base.sanitize_sql_array(["SELECT NOT indisvalid FROM pg_index WHERE indexrelid = to_regclass(:name)", name: "public.#{NAME}"]))
    remove_index :entries, name: NAME, algorithm: :concurrently if invalid
    add_index :entries, [:feed_id, :created_at, :id], name: NAME, algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :entries, name: NAME, algorithm: :concurrently, if_exists: true
  end
end
