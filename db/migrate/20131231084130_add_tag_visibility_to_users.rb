class AddTagVisibilityToUsers < ActiveRecord::Migration[4.2]
  def change
    add_column :users, :tag_visibility, :json, default: {}
  end
end
