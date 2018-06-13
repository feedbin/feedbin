class AddBillingInfoToUsers < ActiveRecord::Migration[4.2]
  def change
    add_column :users, :customer_id, :string
    add_column :users, :last_4_digits, :string
  end
end
