class CreateDiscoveredFeeds < ActiveRecord::Migration[7.0]
  def change
    create_table :discovered_feeds do |t|
      t.text :title
      t.text :site_url
      t.text :feed_url
      t.text :host
      t.datetime :verified_at

      t.timestamps
    end
    add_index :discovered_feeds, [:site_url, :feed_url], unique: true
  end
end
