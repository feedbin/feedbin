class AddShowUpdatesAndMutedToSubscriptions < ActiveRecord::Migration[4.2]
  def up
    add_column :subscriptions, :show_updates, :boolean
    change_column_default(:subscriptions, :show_updates, true)

    add_column :subscriptions, :muted, :boolean
    change_column_default(:subscriptions, :muted, false)

    Subscription.reset_column_information
    SubscriptionBatchScheduler.perform_async
  end

  def down
    remove_column :subscriptions, :show_updates
    remove_column :subscriptions, :muted
  end
end
