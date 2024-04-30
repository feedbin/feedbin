class AddCategoriesToEntry < ActiveRecord::Migration[7.1]
  def change
    add_column :entries, :categories, :jsonb
  end
end
