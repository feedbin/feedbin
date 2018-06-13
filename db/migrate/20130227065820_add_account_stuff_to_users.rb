class AddAccountStuffToUsers < ActiveRecord::Migration[4.2]
  def change
    add_column :users, :auth_token, :string
    add_column :users, :password_reset_token, :string
    add_column :users, :password_reset_sent_at, :datetime

    add_index :users, :email, unique: true
    add_index :users, :customer_id, unique: true
    add_index :users, :password_reset_token, unique: true
  end
end
