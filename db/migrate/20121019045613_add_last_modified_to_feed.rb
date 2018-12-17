class AddLastModifiedToFeed < ActiveRecord::Migration[4.2]
  def change
    add_column :feeds, :last_modified, :datetime
  end
end
