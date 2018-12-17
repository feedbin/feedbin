class AddUrlNewToFavicon < ActiveRecord::Migration[5.1]
  def change
    add_column :favicons, :url_new, :text
  end
end
