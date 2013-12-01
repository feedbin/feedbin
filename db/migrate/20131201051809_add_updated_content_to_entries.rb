class AddUpdatedContentToEntries < ActiveRecord::Migration
  def change
    add_column :entries, :updated_content, :text
  end
end
