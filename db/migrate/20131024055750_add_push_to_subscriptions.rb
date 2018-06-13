class AddPushToSubscriptions < ActiveRecord::Migration[4.2]
  def change
    add_column :subscriptions, :push, :boolean, default: false
  end
end
