class Feed < ActiveRecord::Base
  has_many :subscriptions
  has_many :entries
  has_many :users, through: :subscriptions
  has_many :unread_entries
  has_many :starred_entries

  has_many :taggings
  has_many :tags, through: :taggings

  attr_accessor :unread_count, :tags

  def tag(names, user, delete_existing = true)
    taggings = []
    if delete_existing
      Tagging.delete_all(user_id: user, feed_id: self.id)
    end
    names.split(",").map do |name|
      name = name.strip
      unless name.blank?
        tag = Tag.where(name: name.strip).first_or_create!
        taggings << self.taggings.where(user: user, tag: tag).first_or_create!
      end
    end
    taggings
  end

  def self.create_from_feedzirra(feed, site_url)
    feed.url = site_url
    feed_record = self.create!(feed: feed)
    ActiveRecord::Base.transaction do
      feed.entries.each do |entry|
        feed_record.entries.create!(entry: entry)
      end
    end
    feed_record
  end

  def feed=(feed)
    self.etag          = feed.etag
    self.last_modified = feed.last_modified
    self.title         = feed.title
    self.feed_url      = feed.feed_url
    self.site_url      = feed.url
  end

  def cache_key
    additions = []
    if unread_count
      additions << "/#{unread_count}"
    end
    super + additions.join('')
  end

  def check
    options = {}
    unless last_modified.blank?
      options[:if_modified_since] = last_modified
    end
    unless etag.blank?
      options[:if_none_match] = etag
    end
    feed_fetcher = FeedFetcher.new(feed_url)
    feed_fetcher.fetch_and_parse(options, feed_url)
  end

  def self.include_user_title
    select('feeds.*, subscriptions.title AS user_title').
      map {|feed|
        if feed.user_title
          feed.title = feed.user_title
        elsif feed.title
          feed.title = feed.title
        else
          feed.title = '(No title)'
        end
        feed
      }.
      sort_by {|feed| feed.title.try(:downcase)}
  end

  def string_id
    self.id.to_s
  end
end
