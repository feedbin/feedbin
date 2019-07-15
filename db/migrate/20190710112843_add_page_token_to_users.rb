class AddPageTokenToUsers < ActiveRecord::Migration[5.1]
  disable_ddl_transaction!

  def up
    add_column :users, :page_token, :string
    add_index :users, :page_token, unique: true, algorithm: :concurrently
    User.reset_column_information
    User.find_each do |user|
      user.generate_token(:page_token)
      user.save
    end
  end

  def down
    remove_column :users, :page_token
  end
end
