class AddDataToFavicons < ActiveRecord::Migration[4.2]
  def change
    add_column :favicons, :data, :json
  end
end
