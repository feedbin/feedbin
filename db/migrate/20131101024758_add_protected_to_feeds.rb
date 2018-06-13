class AddProtectedToFeeds < ActiveRecord::Migration[4.2]
  def change
    add_column :feeds, :protected, :boolean, default: false
  end
end
