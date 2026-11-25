# One row per subscription a store bills: Apple's original transaction or
# Google's purchase token. It always belongs to an account. A notification
# for a transaction no account has presented stays an event
# (app_store_notifications, whose user may now be absent) until one does.
class CreateStoreSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :store_subscriptions do |t|
      t.references :user, null: false, foreign_key: {on_delete: :cascade}
      t.integer :store, null: false
      t.text :external_id, null: false
      t.text :app_identifier, null: false
      t.text :environment, null: false
      t.text :product_id, null: false
      t.integer :status, null: false
      t.datetime :expires_at
      t.datetime :grace_expires_at
      t.boolean :auto_renew, null: false, default: true
      t.text :renews_as
      t.bigint :price_milliunits
      t.text :currency
      t.datetime :signed_at
      t.datetime :verified_at
      t.datetime :moved_at
      t.timestamps
    end
    add_index :store_subscriptions, [:store, :external_id], unique: true
    add_index :store_subscriptions, [:status, :expires_at]

    change_column_null :app_store_notifications, :user_id, true

    add_column :deleted_users, :store_subscriptions, :jsonb, null: false, default: []
    add_column :deleted_users, :store_billing_notified_at, :datetime
  end
end
