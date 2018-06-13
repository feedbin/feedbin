class AddImageUrlToEntries < ActiveRecord::Migration[4.2]
  def change
    add_column :entries, :image_url, :text
    add_column :entries, :processed_image_url, :text
  end
end
