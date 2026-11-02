# Unread collection pages are keyed on (entry_created_at, entry_id) for one
# user; without this they sort every unread row the user has.
class AddUnreadsUserEntryCreatedAtIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # if_not_exists: build it ahead of the deploy if the table is too big to
    # wait on. An interrupted concurrent build leaves an INVALID index; drop
    # it and run this again.
    add_index :unreads, [:user_id, :entry_created_at, :entry_id], algorithm: :concurrently, if_not_exists: true
  end
end
