class RemoveUrlNewFromFavicons < ActiveRecord::Migration[5.1]
  def change
    remove_column :favicons, :url_new, :text
  end
end
