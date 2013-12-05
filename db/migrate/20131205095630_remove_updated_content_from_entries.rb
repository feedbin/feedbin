class RemoveUpdatedContentFromEntries < ActiveRecord::Migration
  def change
    remove_column :entries, :updated_content
  end
end
