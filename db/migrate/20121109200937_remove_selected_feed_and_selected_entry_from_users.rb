class RemoveSelectedFeedAndSelectedEntryFromUsers < ActiveRecord::Migration[4.2]
  def up
    remove_column :users, :selected_feed
    remove_column :users, :selected_entry
  end

  def down
    add_column :users, :selected_feed, :integer
    add_column :users, :selected_entry, :integer
  end
end
