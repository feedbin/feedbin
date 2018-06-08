class RemoveUpdatedContentFromEntries < ActiveRecord::Migration[4.2]
  def change
    remove_column :entries, :updated_content
  end
end
