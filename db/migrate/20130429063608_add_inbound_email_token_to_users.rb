class AddInboundEmailTokenToUsers < ActiveRecord::Migration[4.2]
  def up
    add_column :users, :inbound_email_token, :string
    add_index :users, :inbound_email_token, unique: true
    User.reset_column_information
    User.find_each do |user|
      user.generate_token(:inbound_email_token)
      user.save
    end
  end

  def down
    remove_index :users, :inbound_email_token
    remove_column :users, :inbound_email_token, :string
  end
end
