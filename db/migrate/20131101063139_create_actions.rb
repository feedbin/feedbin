class CreateActions < ActiveRecord::Migration
  def change
    create_table :actions do |t|
      t.belongs_to :user, index: true
      t.text :query
      t.text :actions, array: true, default: []
      t.text :feed_ids, array: true, default: []

      t.timestamps
    end
  end
end
