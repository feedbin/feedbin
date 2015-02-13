class Subscription < ActiveRecord::Base
  attr_accessor :entries_count

  belongs_to :user
  belongs_to :feed, counter_cache: true

  before_create :mark_as_unread
  before_destroy :mark_as_read

  before_create :expire_stat_cache
  before_destroy :expire_stat_cache

  after_create :add_feed_to_action
  before_destroy :remove_feed_from_action

  before_destroy :untag

  after_create :update_favicon_hash

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

  def add_feed_to_action
    actions = Action.where(user_id: self.user_id, all_feeds: true)
    actions.each do |action|
      unless action.feed_ids.include?(self.feed_id.to_s)
        action.feed_ids = action.feed_ids + [self.feed_id.to_s]
        action.save
      end
    end
  end

  def remove_feed_from_action
    actions = Action.where(user_id: self.user_id)
    actions.each do |action|
      action.feed_ids = action.feed_ids - [self.feed_id.to_s]
      action.save
    end
  end

  def expire_stat_cache
    Rails.cache.delete("#{self.user_id}:entry_counts")
  end

  def update_favicon_hash
    UpdateFaviconHash.perform_async(self.user_id)
  end

  def untag
    self.feed.tag('', self.user)
  end

  def show_updates?
    self.show_updates
  end

  def muted?
    self.muted == true
  end

end
