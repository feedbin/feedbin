class CreateFeedStats < ActiveRecord::Migration[4.2]
  def change
    create_table :feed_stats do |t|
      t.belongs_to :feed, index: true
      t.date :day
      t.integer :entries_count, default: 0
      t.timestamps
    end
    add_index :feed_stats, [:feed_id, :day]
  end
end
