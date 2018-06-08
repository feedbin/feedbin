class AddUpdatedContentToEntries < ActiveRecord::Migration[4.2]
  def change
    add_column :entries, :updated_content, :text
  end
end
