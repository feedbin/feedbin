class AddUserIdFeedIdIndexToTaggings < ActiveRecord::Migration[4.2]
  def change
    add_index :taggings, [:user_id, :feed_id]
  end
end
