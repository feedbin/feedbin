class CreateFeeds < ActiveRecord::Migration[4.2]
  def change
    create_table :feeds do |t|
      t.string :feed_title
      t.string :feed_url
      t.string :site_url
      t.string :etag

      t.timestamps
    end

    add_index :feeds, :feed_url, unique: true
  end
end
