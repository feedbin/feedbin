class AddSelectedFeedToUsers < ActiveRecord::Migration[4.2]
  def change
    add_column :users, :selected_feed, :integer
  end
end
