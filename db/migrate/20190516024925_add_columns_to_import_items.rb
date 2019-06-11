class AddColumnsToImportItems < ActiveRecord::Migration[5.1]
  def change
    add_column :import_items, :status, :bigint, default: 1, null: false
    add_index :import_items, [:import_id, :status]
  end
end
