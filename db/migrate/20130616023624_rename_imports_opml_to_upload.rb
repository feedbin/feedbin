class RenameImportsOpmlToUpload < ActiveRecord::Migration
  def change
    rename_column :imports, :opml, :upload
  end
end
