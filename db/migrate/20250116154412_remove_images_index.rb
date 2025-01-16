class RemoveImagesIndex < ActiveRecord::Migration[7.2]
  def up
    remove_index :images, [:provider, :provider_id]
  end
  def down
  end
end
