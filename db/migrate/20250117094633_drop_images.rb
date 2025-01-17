class DropImages < ActiveRecord::Migration[7.2]
  def change
    drop_table :images
  end
end
