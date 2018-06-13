class CreateImports < ActiveRecord::Migration[4.2]
  def change
    create_table :imports do |t|
      t.integer :user_id
      t.boolean :complete

      t.timestamps
    end
  end
end
