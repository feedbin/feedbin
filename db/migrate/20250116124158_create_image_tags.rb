class CreateImageTags < ActiveRecord::Migration[7.2]
  def change
    create_table :image_tags do |t|
      t.references :image, null: false, foreign_key: true
      t.references :imageable, polymorphic: true, null: false

      t.timestamps
    end
    add_index :image_tags, [:imageable_id, :image_id, :imageable_type], unique: true
  end
end
