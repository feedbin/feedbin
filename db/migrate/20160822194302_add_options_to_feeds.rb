class AddOptionsToFeeds < ActiveRecord::Migration
  def change
    add_column :feeds, :options, :json
  end
end
