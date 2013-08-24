class RemoveImagesFromEntries < ActiveRecord::Migration
  def change
    remove_column :entries, :images
  end
end
