class RemoveImagesFromEntries < ActiveRecord::Migration[4.2]
  def change
    remove_column :entries, :images
  end
end
