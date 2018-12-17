class CreateSuggestedCategories < ActiveRecord::Migration[4.2]
  def change
    create_table :suggested_categories do |t|
      t.text :name

      t.timestamps
    end
  end
end
