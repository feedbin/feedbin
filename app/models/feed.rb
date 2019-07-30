class Feed < ApplicationRecord
  has_many :subscriptions
  has_many :entries
  has_many :users, through: :subscriptions
  has_many :unread_entries
  has_many :starred_entries
  has_many :feed_stats

  has_many :taggings
  has_many :tags, through: :taggings

  has_one :favicon, foreign_key: "host", primary_key: "host"

  before_create :set_host
  after_create :refresh_favicon

  attr_accessor :count, :tags
  attr_readonly :feed_url

  after_initialize :default_values

  enum feed_type: {xml: 0, newsletter: 1, twitter: 2, twitter_home: 3, pages: 4}

  def twitter_user?
    twitter_user.present?
  end

  def twitter_user
    @twitter_user ||= Twitter::User.new(options["twitter_user"].deep_symbolize_keys)
  rescue
    nil
  end

  def twitter_feed?
    twitter? || twitter_home?
  end

  def tag_with_params(params, user)
    tags = []
    tags.concat params[:tag_id].values if params[:tag_id]
    tags.concat params[:tag_name] if params[:tag_name]
    tags = tags.join(",")
    tag(tags, user)
  end

  def tag(names, user, delete_existing = true)
    taggings = []
    if delete_existing
      Tagging.where(user_id: user, feed_id: id).destroy_all
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

  def host_letter
    letter = "default"
    if host
      if segment = host.split(".")[-2]
        letter = segment[0].downcase
      end
    end
    letter
  end

  def icon
    options.dig("json_feed", "icon")
  end

  def self.create_from_parsed_feed(parsed_feed)
    ActiveRecord::Base.transaction do
      record = create!(parsed_feed.to_feed)
      parsed_feed.entries.each do |parsed_entry|
        entry_hash = parsed_entry.to_entry
        threader = Threader.new(entry_hash, record)
        unless threader.thread
          record.entries.create!(entry_hash)
        end
      end
      record
    end
  end

  def check
    options = {}
    unless last_modified.blank?
      options[:if_modified_since] = last_modified
    end
    unless etag.blank?
      options[:if_none_match] = etag
    end
    request = Feedkit::Request.new(url: feed_url, options: options)
    result = request.status
    if request.body
      result = Feedkit::Feedkit.new.fetch_and_parse(feed_url, request: request)
    end
    result
  end

  def self.include_user_title
    feeds = select("feeds.*, subscriptions.title AS user_title")
    feeds.map do |feed|
      if feed.user_title
        feed.override_title(feed.user_title)
      end
      feed.title ||= "Untitled"
      feed
    end
    feeds.natural_sort_by { |feed| feed.title }
  end

  def string_id
    id.to_s
  end

  def set_host
    self.host = URI.parse(site_url).host
  rescue Exception
    Rails.logger.info { "Failed to set host for feed: %s" % site_url }
  end

  def override_title(title)
    @original_title = self.title
    self.title = title
  end

  def original_title
    @original_title || title
  end

  def priority_refresh(user = nil)
    if twitter_feed?
      if 10.minutes.ago > updated_at
        TwitterFeedRefresher.new.enqueue_feed(self, user)
      end
    else
      Sidekiq::Client.push_bulk(
        "args" => [[id, feed_url]],
        "class" => "FeedRefresherFetcherCritical",
        "queue" => "feed_refresher_fetcher_critical",
        "retry" => false,
      )
    end
  end

  def list_unsubscribe
    options.dig("email_headers", "List-Unsubscribe")
  end

  def self.search(url)
    where("feed_url ILIKE :query", query: "%#{url}%")
  end

  def json_feed
    options&.respond_to?(:dig) && options.dig("json_feed")
  end

  def has_subscribers?
    subscriptions_count > 0
  end

  private

  def refresh_favicon
    FaviconFetcher.perform_async(host)
  end

  def default_values
    if respond_to?(:options)
      self.options ||= {}
    end
  end
end
