class AddUrlToFavicons < ActiveRecord::Migration[5.0]
  def change
    add_column :favicons, :url, :string
  end
end
