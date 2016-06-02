class AddDataToFavicons < ActiveRecord::Migration
  def change
    add_column :favicons, :data, :json
  end
end
