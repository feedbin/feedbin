class AddLastPublishedEntryToFeeds < ActiveRecord::Migration
  def up
    add_column :feeds, :last_published_entry, :datetime
    add_index :feeds, :last_published_entry
  end

  def down
    remove_column :feeds, :last_published_entry
  end
end
