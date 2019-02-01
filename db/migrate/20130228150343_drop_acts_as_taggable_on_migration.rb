class DropActsAsTaggableOnMigration < ActiveRecord::Migration[4.2]
  def up
    drop_table :taggings
    drop_table :tags
  end

  def down
    create_table :tags do |t|
      t.string :name
    end
    create_table :taggings do |t|
      t.references :tag
      t.references :taggable, polymorphic: true
      t.references :tagger, polymorphic: true
      t.string :context, limit: 128
      t.datetime :created_at
    end
    add_index :taggings, :tag_id
    add_index :taggings, [:taggable_id, :taggable_type, :context]
  end
end
