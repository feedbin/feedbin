class AddHostToFeeds < ActiveRecord::Migration[4.2]
  def change
    add_column :feeds, :host, :text
    add_index :feeds, :host
  end
end
