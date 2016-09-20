class Subscription < ApplicationRecord
  attr_accessor :entries_count, :post_volume

  belongs_to :user
  belongs_to :feed, counter_cache: true

  after_commit :mark_as_unread, on: [:create]
  before_destroy :mark_as_read

  before_create :expire_stat_cache
  before_destroy :expire_stat_cache

  after_create :add_feed_to_action
  after_commit :remove_feed_from_action, on: [:destroy]

  before_create :refresh_feed

  before_destroy :untag
  before_destroy :email_unsubscribe

  after_create :update_favicon_hash
  after_create :refresh_favicon

  def mark_as_unread
    base = Entry.select(:id, :feed_id, :published, :created_at).where(feed_id: self.feed_id).order('published DESC')
    entries = base.where('published > ?', Time.now.ago(2.weeks)).limit(10)
    if entries.length == 0
      entries = base.limit(3)
    end
    unread_entries = entries.map do |entry|
      UnreadEntry.new_from_owners(self.user, entry)
    end
    UnreadEntry.import(unread_entries, validate: false)
  end

  def mark_as_read
    UnreadEntry.where(user_id: self.user_id, feed_id: self.feed_id).delete_all
  end

  def add_feed_to_action
    actions = Action.where(user_id: self.user_id, all_feeds: true)
    actions.each do |action|
      action.save
    end
  end

  def remove_feed_from_action
    actions = Action.where(user_id: self.user_id)
    actions.each do |action|
      action.feed_ids = action.feed_ids - [self.feed_id.to_s]
      action.automatic_modification = true
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

  def refresh_feed
    if feed_already_existed? && !any_subscribers?
      self.feed.priority_refresh
      sleep(3)
    end
  end

  def any_subscribers?
    Subscription.where(feed_id: self.feed_id, active: true, muted: false).exists?
  end

  def feed_already_existed?
    self.feed.created_at < 1.minute.ago
  end

  private

  def email_unsubscribe
    EmailUnsubscribe.perform_async(self.feed_id)
  end

  def refresh_favicon
    FaviconFetcher.perform_async(self.feed.host)
  end

end
