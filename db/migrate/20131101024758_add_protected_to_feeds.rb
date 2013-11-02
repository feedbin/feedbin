class AddProtectedToFeeds < ActiveRecord::Migration
  def change
    add_column :feeds, :protected, :boolean, default: false
  end
end
