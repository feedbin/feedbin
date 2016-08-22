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
  attr_readonly :feed_url

  after_initialize :default_values

  enum feed_type: { xml: 0, newsletter: 1 }

  def tag(names, user, delete_existing = true)
    taggings = []
    if delete_existing
      Tagging.destroy_all(user_id: user, feed_id: self.id)
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

  def self.create_from_parsed_feed(parsed_feed)
    record = self.create!(parsed_feed.to_feed)
    parsed_feed.entries.each do |parsed_entry|
      record.entries.create!(parsed_entry.to_entry)
    end
    record
  end

  def check
    options = {}
    unless last_modified.blank?
      options[:if_modified_since] = last_modified
    end
    unless etag.blank?
      options[:if_none_match] = etag
    end
    request = FeedRequest.new(url: self.feed_url, options: options)
    result = request.status
    if request.body
      result = ParsedFeed.new(request.body, request)
    end
    result
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

  def priority_refresh
    Sidekiq::Client.push_bulk(
      'args'  => [[self.id, self.feed_url]],
      'class' => 'FeedRefresherFetcherCritical',
      'queue' => 'feed_refresher_fetcher_critical',
      'retry' => false
    )
  end

  def list_unsubscribe
    self.options.dig('email_headers', 'List-Unsubscribe')
  end

  private

  def default_values
    self.options ||= {}
  end

end
