class WebSubUpdates < ActiveRecord::Migration[6.0]
  disable_ddl_transaction!

  def change
    add_column :feeds, :hubs, :text, array: true
    add_index :feeds, :push_expiration, where: "push_expiration IS NOT NULL", algorithm: :concurrently
    add_index :feeds, :hubs, where: "hubs IS NOT NULL", algorithm: :concurrently
  end
end
