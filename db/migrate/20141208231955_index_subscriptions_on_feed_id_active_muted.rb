class IndexSubscriptionsOnFeedIdActiveMuted < ActiveRecord::Migration
  disable_ddl_transaction!
  def change
    add_index :subscriptions, [:feed_id, :active, :muted], algorithm: :concurrently
  end
end
