class CreateSuggestedCategories < ActiveRecord::Migration
  def change
    create_table :suggested_categories do |t|
      t.text :name

      t.timestamps
    end
  end
end
