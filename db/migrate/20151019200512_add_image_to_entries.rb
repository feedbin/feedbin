class AddImageToEntries < ActiveRecord::Migration[4.2]
  def change
    add_column :entries, :image, :json
  end
end
