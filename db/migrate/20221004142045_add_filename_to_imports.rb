class AddFilenameToImports < ActiveRecord::Migration[7.0]
  def change
    add_column :imports, :filename, :text
    add_column :import_items, :error, :jsonb
  end
end
