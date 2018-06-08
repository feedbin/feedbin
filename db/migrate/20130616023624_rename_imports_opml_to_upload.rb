class RenameImportsOpmlToUpload < ActiveRecord::Migration[4.2]
  def change
    rename_column :imports, :opml, :upload
  end
end
