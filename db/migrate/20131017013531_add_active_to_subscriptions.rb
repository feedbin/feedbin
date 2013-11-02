class AddActiveToSubscriptions < ActiveRecord::Migration
  def change
    add_column :subscriptions, :active, :boolean, default: true
  end
end
