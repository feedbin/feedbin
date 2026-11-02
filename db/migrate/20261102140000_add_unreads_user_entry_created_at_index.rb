# Unread collection pages are keyed on (entry_created_at, entry_id) for one
# user; without this they sort every unread row the user has.
class AddUnreadsUserEntryCreatedAtIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :unreads, [:user_id, :entry_created_at, :entry_id], algorithm: :concurrently
  end
end
