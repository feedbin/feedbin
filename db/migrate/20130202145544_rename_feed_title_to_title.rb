class RenameFeedTitleToTitle < ActiveRecord::Migration[4.2]
  def change
    rename_column :feeds, :feed_title, :title
  end
end
