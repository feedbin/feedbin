class AddIndexes < ActiveRecord::Migration[4.2]
  def change
    add_index :users, :auth_token, unique: true
    add_index :taggings, [:user_id, :tag_id]
  end
end
