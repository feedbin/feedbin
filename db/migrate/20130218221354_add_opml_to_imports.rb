class AddOpmlToImports < ActiveRecord::Migration[4.2]
  def change
    add_column :imports, :opml, :string
  end
end
