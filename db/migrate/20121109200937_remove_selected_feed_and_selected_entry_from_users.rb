class RemoveSelectedFeedAndSelectedEntryFromUsers < ActiveRecord::Migration
  def up
    remove_column :users, :selected_feed
    remove_column :users, :selected_entry
  end

  def down
    add_column :users, :selected_feed, :integer
    add_column :users, :selected_entry, :integer
  end
end
