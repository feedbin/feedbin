class AddOptionsToFeeds < ActiveRecord::Migration[4.2]
  def change
    add_column :feeds, :options, :json
  end
end
