class Subscription < ApplicationRecord
  attr_accessor :entries_count, :post_volume, :sort_data, :tag_names

  belongs_to :user
  belongs_to :feed, counter_cache: true

  after_commit :mark_as_unread, on: [:create]

  before_create :expire_stat_cache

  after_create :add_feed_to_action
  after_commit :remove_feed_from_action, on: [:destroy]
  after_commit :cache_entry_ids, on: [:create, :destroy]

  before_destroy :prevent_generated_destroy
  before_destroy :mark_as_read
  before_destroy :untag

  after_create :refresh_favicon

  validate :reject_title_chages, on: :update, if: :generated?

  def reject_title_chages
   errors[:title] << "can not be changed" if self.title_changed?
  end

  enum kind: {default: 0, generated: 1}

  def self.create_multiple(feeds, user, valid_feed_ids)
    @subscriptions = feeds.each_with_object([]) { |(feed_id, subscription), array|
      feed = Feed.find(feed_id)
      if valid_feed_ids.include?(feed.id) && subscription["subscribe"] == "1"
        record = user.subscriptions.find_or_create_by(feed: feed)
        record.update(title: subscription["title"].strip, media_only: subscription["media_only"])
        array.push(record)
      end
    }
  end

  def title
    self[:title] || feed.title
  end

  def mark_as_unread
    base = Entry.select(:id, :feed_id, :published, :created_at).where(feed_id: feed_id).order("published DESC")
    entries = base.where("published > ?", Time.now.ago(2.weeks)).limit(10)
    if entries.length == 0
      entries = base.limit(3)
    end
    unread_entries = entries.map { |entry|
      UnreadEntry.new_from_owners(user, entry)
    }
    UnreadEntry.import(unread_entries, validate: false)
  end

  def mark_as_read
    UnreadEntry.where(user_id: user_id, feed_id: feed_id).delete_all
  end

  def add_feed_to_action
    AddFeedToAction.perform_async(user_id)
  end

  def remove_feed_from_action
    RemoveFeedFromAction.perform_async(user_id, feed_id)
  end

  def expire_stat_cache
    Rails.cache.delete("#{user_id}:entry_counts")
  end

  def untag
    feed.tag("", user)
  end

  def prevent_generated_destroy
    if generated?
      throw(:abort)
    else
      true
    end
  end

  def muted_status
    if muted
      "muted"
    end
  end

  private

  def refresh_favicon
    FaviconFetcher.perform_async(feed.host)
  end

  def cache_entry_ids
    RedisServerSetup.new.perform(feed_id)
  end
end
