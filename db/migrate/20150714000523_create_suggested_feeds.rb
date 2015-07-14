class CreateSuggestedFeeds < ActiveRecord::Migration
  def change
    create_table :suggested_feeds do |t|
      t.belongs_to :suggested_category, index: true
      t.references :feed, index: true

      t.timestamps
    end
  end
end
