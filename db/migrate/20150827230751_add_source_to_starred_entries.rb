class AddSourceToStarredEntries < ActiveRecord::Migration
  def change
    add_column :starred_entries, :source, :text
  end
end
