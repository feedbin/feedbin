# The store's own identifier for the account that pays (Apple's
# appTransactionId: one per Apple Account, per app). Apple sometimes starts a
# subscription afresh for someone it already bills, under a new transaction
# and with no token; this is what says it is the same person.
class AddStoreAccountIdToStoreSubscriptions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :store_subscriptions, :store_account_id, :text
    add_index :store_subscriptions, [:store, :store_account_id], algorithm: :concurrently
  end
end
