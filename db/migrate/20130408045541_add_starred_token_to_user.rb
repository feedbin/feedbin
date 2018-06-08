class AddStarredTokenToUser < ActiveRecord::Migration[4.2]
  def up
    add_column :users, :starred_token, :string
    add_index :users, :starred_token, unique: true
    User.reset_column_information
    User.find_each do |user|
      user.generate_token(:starred_token)
      user.save
    end
  end

  def down
    remove_index :users, :starred_token
    remove_column :users, :starred_token, :string
  end
end
