class AddNewsletterTokenToUsers < ActiveRecord::Migration
  def up
    add_column :users, :newsletter_token, :string
    add_index :users, :newsletter_token, unique: true
    User.reset_column_information
    User.find_each do |user|
      user.generate_token(:newsletter_token)
      user.save
    end
  end

  def down
    remove_index :users, :newsletter_token
    remove_column :users, :newsletter_token, :string
  end
end
