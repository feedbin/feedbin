class CreateTaggings < ActiveRecord::Migration[4.2]
  def change
    create_table :taggings do |t|
      t.belongs_to :tag
      t.belongs_to :feed
      t.belongs_to :user

      t.timestamps
    end
    add_index :taggings, :tag_id
    add_index :taggings, :feed_id
    add_index :taggings, :user_id
  end
end
