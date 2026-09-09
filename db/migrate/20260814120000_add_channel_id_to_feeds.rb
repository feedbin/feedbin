class AddChannelIdToFeeds < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :feeds, :channel_id, :text
    add_index :feeds, :channel_id, algorithm: :concurrently
  end
end
