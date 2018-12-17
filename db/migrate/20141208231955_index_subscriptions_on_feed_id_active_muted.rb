class IndexSubscriptionsOnFeedIdActiveMuted < ActiveRecord::Migration[4.2]
  disable_ddl_transaction!

  def change
    add_index :subscriptions, [:feed_id, :active, :muted], algorithm: :concurrently
    add_index :subscriptions, [:feed_id, :active, :muted, :show_updates], algorithm: :concurrently, name: "index_subscriptions_on_updates"
  end
end
