class AddSelfUrlToFeed < ActiveRecord::Migration
  def change
    add_column :feeds, :self_url, :text
  end
end
