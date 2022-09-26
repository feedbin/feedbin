class UpdateRefreshMetadataOnFeeds < ActiveRecord::Migration[7.0]
  def change
    add_column :feeds, :crawl_data, :jsonb
    safety_assured do
      remove_column :feeds, :etag, :text
      remove_column :feeds, :last_modified, :datetime
      remove_column :feeds, :fingerprint, :uuid
    end
  end
end


