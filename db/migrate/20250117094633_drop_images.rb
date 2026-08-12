class DropImages < ActiveRecord::Migration[7.2]
  def change
    drop_table :image_tags, if_exists: true
    drop_table :images, if_exists: true
  end
end
