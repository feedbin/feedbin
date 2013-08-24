class AddItemTypeToImportItems < ActiveRecord::Migration
  def change
    add_column :import_items, :item_type, :string
  end
end
