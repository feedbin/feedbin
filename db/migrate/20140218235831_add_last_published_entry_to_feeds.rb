class AddLastPublishedEntryToFeeds < ActiveRecord::Migration
  def up
    add_column :feeds, :last_published_entry, :datetime
    add_index :feeds, :last_published_entry

    Feed.reset_column_information

    Feed.find_each do |feed|
      most_recent_entry = Entry.select(:published).where(feed_id: feed.id).order('published DESC').limit(1).first
      if most_recent_entry.present?
        feed.last_published_entry = most_recent_entry.published
        feed.save
      end
    end
  end

  def down
    remove_column :feeds, :last_published_entry
  end
end
