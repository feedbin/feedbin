class AddStoragePathIndexToImages < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :images, :storage_path, algorithm: :concurrently
  end
end
