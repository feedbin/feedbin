class AddSelectedFeedToUsers < ActiveRecord::Migration
  def change
    add_column :users, :selected_feed, :integer
  end
end
