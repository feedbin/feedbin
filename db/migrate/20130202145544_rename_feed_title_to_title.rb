class RenameFeedTitleToTitle < ActiveRecord::Migration
  def change
    rename_column :feeds, :feed_title, :title
  end
end
