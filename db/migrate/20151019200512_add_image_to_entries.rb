class AddImageToEntries < ActiveRecord::Migration
  def change
    add_column :entries, :image, :json
  end
end
