class AddPushToSubscriptions < ActiveRecord::Migration
  def change
    add_column :subscriptions, :push, :boolean, default: false
  end
end
