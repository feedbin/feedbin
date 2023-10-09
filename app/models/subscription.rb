class Subscription < ApplicationRecord
  attr_accessor :entries_count, :post_volume, :sort_data, :tag_names

  belongs_to :user
  belongs_to :feed, counter_cache: true

  after_commit :mark_as_unread, on: [:create]

  before_create :expire_stat_cache

  after_create :add_feed_to_action
  after_commit :remove_feed_from_action, on: [:destroy]

  before_destroy :prevent_generated_destroy
  before_destroy :mark_as_read
  before_destroy :untag

  after_create :refresh_favicon

  validate :reject_title_changes, on: :update, if: :generated?

  def reject_title_changes
    errors[:title] << "can not be changed" if title_changed?
  end

  enum kind: {default: 0, generated: 1}
  enum view_mode: {article: 0, extract: 1, newsletter: 2}
  enum show_status: {not_show: 0, hidden: 1, subscribed: 2, bookmarked: 3}
  enum fix_status: {none: 0, present: 1, ignored: 2}, _prefix: :fix_suggestion

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
    UnreadEntry.import(unread_entries, validate: false, on_duplicate_key_ignore: true)
  end

  def mark_as_read
    UnreadEntry.where(user_id: user_id, feed_id: feed_id).delete_all
  end

  def add_feed_to_action
    Search::AddFeedToAction.perform_async(user_id)
  end

  def remove_feed_from_action
    Search::RemoveFeedFromAction.perform_async(user_id, feed_id)
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

  def protected?
    generated?
  end
  
  def replaceable_path
    Rails.application.routes.url_helpers.fix_feed_path(self)
  end

  private

  def refresh_favicon
    FaviconCrawler::Finder.perform_async(feed.host)
    ImageCrawler::ItunesFeedImage.perform_async(feed_id)
  end
end
