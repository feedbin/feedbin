class AddNewsletterTokenToUsers < ActiveRecord::Migration[4.2]
  def up
    add_column :users, :newsletter_token, :string
    add_index :users, :newsletter_token, unique: true
  end

  def down
    remove_index :users, :newsletter_token
    remove_column :users, :newsletter_token, :string
  end
end
