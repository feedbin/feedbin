class Feed < ActiveRecord::Base
  has_many :subscriptions
  has_many :entries
  has_many :users, through: :subscriptions
  has_many :unread_entries
  has_many :starred_entries
  has_many :feed_stats

  has_many :taggings
  has_many :tags, through: :taggings

  before_create :set_host

  attr_accessor :count, :tags

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

  def self.create_from_feedjira(feed, site_url)
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
    feeds = select('feeds.*, subscriptions.title AS user_title')
    feeds.map do |feed|
      if feed.user_title
        feed.override_title(feed.user_title)
      end
      feed.title ||= '(No title)'
      feed
    end
    feeds.sort_by {|feed| feed.title.try(:downcase)}
  end

  def string_id
    self.id.to_s
  end

  def set_host
    begin
      self.host = URI::parse(self.site_url).host
      FaviconFetcher.perform_async(self.host)
    rescue Exception
      Rails.logger.info { "Failed to set host for feed: %s" %  self.site_url}
    end
  end

  def override_title(title)
    @original_title = self.title
    self.title=(title)
  end

  def original_title
    @original_title or self.title
  end
end
