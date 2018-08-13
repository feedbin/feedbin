class CreateImportItems < ActiveRecord::Migration[4.2]
  def change
    create_table :import_items do |t|
      t.integer :import_id
      t.text :details

      t.timestamps
    end

    add_index :import_items, :import_id
  end
end
