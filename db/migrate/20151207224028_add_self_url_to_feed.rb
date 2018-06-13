class AddSelfUrlToFeed < ActiveRecord::Migration[4.2]
  def change
    add_column :feeds, :self_url, :text
  end
end
