class AddProviderDataToFeeds < ActiveRecord::Migration[7.0]
  def change
    add_column :feeds, :provider, :bigint
    add_column :feeds, :provider_id, :text
    add_column :feeds, :provider_parent_id, :text
  end
end
