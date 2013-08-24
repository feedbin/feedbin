class AddOpmlToImports < ActiveRecord::Migration
  def change
    add_column :imports, :opml, :string
  end
end
