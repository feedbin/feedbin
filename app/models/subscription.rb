class Subscription < ActiveRecord::Base
  belongs_to :user
  belongs_to :feed, counter_cache: true

  before_create :mark_as_unread
  before_destroy :mark_as_read

  def mark_as_unread
    entries = Entry.select(:id, :published, :created_at).where(feed_id: self.feed_id).where('published > ?', Time.now.ago(2.weeks))
    if entries.length == 0
      entries = Entry.select(:id, :published, :created_at).where(feed_id: self.feed_id).order('published DESC').limit(1)
    end
    unread_entries = []
    entries.each do |entry|
      unread_entries << UnreadEntry.new(user_id: self.user_id, feed_id: self.feed_id, entry_id: entry.id, published: entry.published, entry_created_at: entry.created_at)
    end
    UnreadEntry.import(unread_entries, validate: false)
  end

  def mark_as_read
    UnreadEntry.delete_all(user_id: self.user_id, feed_id: self.feed_id)
  end

end
