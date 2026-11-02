# Unread collection pages are keyed on (entry_created_at, entry_id) for one
# user; without this they sort every unread row the user has.
class AddUnreadsUserEntryCreatedAtIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  NAME = "index_unreads_on_user_id_and_entry_created_at_and_entry_id"

  # if_not_exists: the index can be built ahead of the deploy. An interrupted
  # concurrent build leaves an INVALID index under the same name, which
  # if_not_exists would accept, so that one is dropped and built again.
  def up
    invalid = select_value(ActiveRecord::Base.sanitize_sql_array(["SELECT NOT indisvalid FROM pg_index WHERE indexrelid = to_regclass(:name)", name: "public.#{NAME}"]))
    remove_index :unreads, name: NAME, algorithm: :concurrently if invalid
    add_index :unreads, [:user_id, :entry_created_at, :entry_id], name: NAME, algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :unreads, name: NAME, algorithm: :concurrently, if_exists: true
  end
end
