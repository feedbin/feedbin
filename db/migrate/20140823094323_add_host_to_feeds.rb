class AddHostToFeeds < ActiveRecord::Migration
  def change
    add_column :feeds, :host, :text
    add_index :feeds, :host
  end
end
