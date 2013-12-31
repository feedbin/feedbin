class AddTagVisibilityToUsers < ActiveRecord::Migration
  def change
    add_column :users, :tag_visibility, :json, default: {}
  end
end
