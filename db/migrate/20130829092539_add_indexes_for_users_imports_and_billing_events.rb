class AddIndexesForUsersImportsAndBillingEvents < ActiveRecord::Migration
  def change
    add_index :billing_events, [:event_id,:event_type]
    add_index :billing_events, :event_type
    add_index :imports, :user_id
    add_index :users, :plan_id
  end
end
