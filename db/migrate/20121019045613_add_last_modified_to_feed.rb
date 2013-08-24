class AddLastModifiedToFeed < ActiveRecord::Migration
  def change
    add_column :feeds, :last_modified, :datetime
  end
end
