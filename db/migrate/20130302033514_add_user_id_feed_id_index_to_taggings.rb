class AddUserIdFeedIdIndexToTaggings < ActiveRecord::Migration
  def change
    add_index :taggings, [:user_id, :feed_id]
  end
end
