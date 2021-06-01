class AddMainTweetIdToEntries < ActiveRecord::Migration[6.1]
  disable_ddl_transaction!

  def change
    add_column :entries, :main_tweet_id, :text
    add_index :entries, :main_tweet_id, where: "main_tweet_id IS NOT NULL", algorithm: :concurrently
  end
end
