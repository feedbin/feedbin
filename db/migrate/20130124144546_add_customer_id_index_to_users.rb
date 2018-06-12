class AddCustomerIdIndexToUsers < ActiveRecord::Migration[4.2]
  def change
    add_index :users, :customer_id, unique: true
  end
end
