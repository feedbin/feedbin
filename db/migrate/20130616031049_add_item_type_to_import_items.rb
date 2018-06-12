class AddItemTypeToImportItems < ActiveRecord::Migration[4.2]
  def change
    add_column :import_items, :item_type, :string
  end
end
