class CreateActions < ActiveRecord::Migration
  def change
    create_table :actions do |t|
      t.belongs_to :user, index: true
      t.text :query
      t.text :actions, array: true, default: []
      t.text :feed_ids, array: true, default: []
      t.boolean :all_feeds, default: true

      t.timestamps
    end
  end
end
