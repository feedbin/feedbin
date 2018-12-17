class AddOptionsToSubscriptions < ActiveRecord::Migration[5.1]
  disable_ddl_transaction!

  def up
    add_column :subscriptions, :show_retweets, :boolean
    change_column_default(:subscriptions, :show_retweets, true)
    add_index :subscriptions, :show_retweets, algorithm: :concurrently

    add_column :subscriptions, :media_only, :boolean
    change_column_default(:subscriptions, :media_only, false)
    add_index :subscriptions, :media_only, algorithm: :concurrently

    UpdateDefaultColumn.perform_async({
      "klass" => Subscription.to_s,
      "column" => "show_retweets",
      "default" => true,
      "schedule" => true,
    })

    UpdateDefaultColumn.perform_async({
      "klass" => Subscription.to_s,
      "column" => "media_only",
      "default" => false,
      "schedule" => true,
    })
  end

  def down
    remove_column :subscriptions, :show_retweets
    remove_column :subscriptions, :media_only
  end
end
