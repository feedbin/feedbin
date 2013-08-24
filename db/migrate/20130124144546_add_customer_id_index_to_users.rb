class AddCustomerIdIndexToUsers < ActiveRecord::Migration
  def change
    add_index :users, :customer_id, unique: true
  end
end
