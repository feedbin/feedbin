class AddRevisionToEntries < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  NAME = "index_entries_on_edited_at_and_id"

  # The index build scans all of entries, so the columns and the index can be
  # made by hand ahead of the deploy, and each step skips what is already
  # there. An interrupted concurrent build leaves an INVALID index under the
  # same name, which if_not_exists would accept, so that one is dropped and
  # built again.
  def up
    add_column :entries, :revision, :integer, null: false, default: 1, if_not_exists: true
    add_column :entries, :edited_at, :datetime, if_not_exists: true

    invalid = select_value(ActiveRecord::Base.sanitize_sql_array(["SELECT NOT indisvalid FROM pg_index WHERE indexrelid = to_regclass(:name)", name: "public.#{NAME}"]))
    remove_index :entries, name: NAME, algorithm: :concurrently if invalid
    # Only edited entries have one, and API v3's edited_after= reads them in
    # edited_at order.
    add_index :entries, [:edited_at, :id], name: NAME, where: "edited_at IS NOT NULL", algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :entries, name: NAME, algorithm: :concurrently, if_exists: true
    remove_column :entries, :edited_at, if_exists: true
    remove_column :entries, :revision, if_exists: true
  end
end
