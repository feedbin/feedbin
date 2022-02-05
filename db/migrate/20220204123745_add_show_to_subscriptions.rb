class AddShowToSubscriptions < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_column :subscriptions, :show_status, :bigint, default: 0, null: false
    add_index :subscriptions, :show_status, algorithm: :concurrently
  end
end
