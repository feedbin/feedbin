class AddSourceToStarredEntries < ActiveRecord::Migration[4.2]
  def change
    add_column :starred_entries, :source, :text
  end
end
