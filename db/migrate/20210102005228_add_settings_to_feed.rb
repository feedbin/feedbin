class AddSettingsToFeed < ActiveRecord::Migration[6.0]
  def change
    add_column :feeds, :settings, :jsonb
  end
end
