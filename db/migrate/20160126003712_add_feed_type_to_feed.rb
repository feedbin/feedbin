class AddFeedTypeToFeed < ActiveRecord::Migration[4.2]
  disable_ddl_transaction!

  def up
    add_column :feeds, :feed_type, :integer
    change_column_default(:feeds, :feed_type, Feed.feed_types[:xml])
    add_index :feeds, :feed_type, algorithm: :concurrently
  end

  def down
    remove_column :feeds, :feed_type
  end
end
