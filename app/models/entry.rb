class Entry < ApplicationRecord
  include Searchable

  attr_accessor :fully_qualified_url, :read, :starred, :skip_mark_as_unread

  belongs_to :feed
  has_many :unread_entries, dependent: :delete_all
  has_many :starred_entries
  has_many :recently_read_entries

  before_create :ensure_published
  before_create :create_summary
  before_create :update_content
  before_update :create_summary
  after_commit :cache_public_id, on: :create
  after_commit :find_images, on: :create
  after_commit :mark_as_unread, on: :create
  after_commit :add_to_created_at_set, on: :create
  after_commit :add_to_published_set, on: :create
  after_commit :increment_feed_stat, on: :create
  after_commit :touch_feed_last_published_entry, on: :create
  after_commit :save_pages, on: :create

  validate :has_content
  validates :feed, :public_id, presence: true

  self.per_page = 100

  def tweet?
    tweet.present?
  end

  def tweet
    @tweet ||= Twitter::Tweet.new(data["tweet"].deep_symbolize_keys)
  rescue
    nil
  end

  def micropost?
    micropost.present?
  end

  def micropost
    @micropost ||= begin
      if data.respond_to?(:has_key?)
        post = Micropost.new(data["json_feed"], self.title)
        post.valid? ? post : nil
      end
    end
  end

  def twitter_thread_ids
    thread.map do |t|
      t.dig("id")
    end
  end

  def twitter_id
    data && data.dig("tweet", "id")
  end

  def main_tweet
    if self.tweet?
      @main_tweet ||= (self.tweet.retweeted_status?) ? self.tweet.retweeted_status : self.tweet
    end
  end

  def twitter_media?
    media = false
    if self.tweet?
      tweets = [self.main_tweet]
      tweets.push(self.main_tweet.quoted_status) if self.main_tweet.quoted_status?

      media = tweets.find do |tweet|
        return true if tweet.media?
        urls = tweet.urls.reject { |url| url.expanded_url.host == "twitter.com" }
        return true if !urls.empty?
      end
    end
    !!media
  end

  def retweet?
    (self.tweet?) ? self.tweet.retweeted_status? : false
  end

  def tweet_summary(tweet = nil)
    tweet = tweet || self.main_tweet
    hash = tweet.to_h

    text = trim_text(hash, true)
    tweet.urls.reverse.each do |url|
      begin
        range = Range.new(*url.indices, true)
        text[range] = url.display_url
      rescue
      end
    end
    text
  end

  def tweet_text(tweet)
    hash = tweet.to_h
    if hash[:entities]
      hash = remove_entities(hash)
      text = trim_text(hash, false, true)
      text = Twitter::TwitterText::Autolink.auto_link_with_json(text, hash[:entities]).html_safe
    else
      text = hash[:full_text]
    end
    if text.respond_to?(:strip)
      text.strip
    else
      text
    end
  rescue
    hash[:full_text]
  end

  def remove_entities(hash)
    if hash[:display_text_range]
      text_start = hash[:display_text_range].first
      text_end = hash[:display_text_range].last
      hash[:entities].each do |entity, values|
        hash[:entities][entity] = values.reject do |value|
          value[:indices].last < text_start || value[:indices].first > text_end
        end
        hash[:entities][entity].each_with_index do |value, index|
          hash[:entities][entity][index][:indices] = [
            value[:indices][0] - text_start,
            value[:indices][1] - text_start,
          ]
        end
      end
    end
    hash
  end

  def thread
    self.data && self.data.dig("thread") || []
  end

  def tweet_thread
    @tweet_thread ||= begin
      thread.map { |part| Twitter::Tweet.new(part.deep_symbolize_keys) }
    end
  rescue
    []
  end

  def trim_text(hash, exclude_end = false, trim_start = false)
    text = hash[:full_text]
    if range = hash[:display_text_range]
      start = (trim_start) ? range.first : 0
      range = Range.new(start, range.last, exclude_end)
      text = text.codepoints[range].pack("U*")
    end
    text
  end

  def has_content
    if [title, url, entry_id, content].compact.count == 0
      errors.add(:base, "entry has no content")
    end
  end

  def self.entries_with_feed(entry_ids, sort)
    entry_ids = entry_ids.map(&:entry_id)
    entries = Entry.where(id: entry_ids).includes(feed: [:favicon])
    if sort == "ASC"
      entries = entries.order("published ASC")
    else
      entries = entries.order("published DESC")
    end
    entries
  end

  def self.entries_list
    select(:id, :feed_id, :title, :summary, :published, :image, :data, :author, :url)
  end

  def self.include_unread_entries(user_id)
    joins("LEFT OUTER JOIN unread_entries ON entries.id = unread_entries.entry_id AND unread_entries.user_id = #{user_id.to_i}")
  end

  def self.unread_new
    where("unread_entries.entry_id IS NOT NULL")
  end

  def self.read_new
    where("unread_entries.entry_id IS NULL")
  end

  def self.include_starred_entries(user_id)
    joins("LEFT OUTER JOIN starred_entries ON entries.id = starred_entries.entry_id AND starred_entries.user_id = #{user_id.to_i}")
  end

  def self.unstarred_new
    where("starred_entries.entry_id IS NULL")
  end

  def self.sort_preference(sort)
    if sort == "ASC"
      order("published ASC")
    else
      order("published DESC")
    end
  end

  def fully_qualified_url
    entry_url = self.url
    if entry_url.present? && is_fully_qualified(entry_url)
      entry_url = entry_url
    elsif entry_url.present?
      entry_url = URI.join(base_url, entry_url).to_s
    else
      entry_url = self.feed.site_url
    end
    entry_url = Addressable::URI.unescape(entry_url)
    entry_url = Addressable::URI.escape(entry_url)
    entry_url.gsub(Feedbin::Application.config.entities_regex, Feedbin::Application.config.entities_map)
  rescue
    self.feed.site_url
  end

  def content_format
    self.data && self.data["format"] || "default"
  end

  def as_indexed_json(options = {})
    base = as_json(root: false, only: Entry.mappings.to_hash[:entry][:properties].keys.reject { |key| key.to_s.start_with?("twitter") })
    base["title"] = ContentFormatter.summary(self.title)
    base["content"] = ContentFormatter.summary(self.content)
    base["emoji"] = (base["title"] + base["content"]).scan(Unicode::Emoji::REGEX).join(" ")

    if self.tweet?
      tweets = [self.main_tweet]
      tweets.push(self.main_tweet.quoted_status) if self.main_tweet.quoted_status?
      base["twitter_screen_name"] = "#{self.main_tweet.user.screen_name} @#{self.main_tweet.user.screen_name}"
      base["twitter_name"] = self.main_tweet.user.name
      base["twitter_retweet"] = self.tweet.retweeted_status?
      base["twitter_quoted"] = self.tweet.quoted_status?
      base["twitter_media"] = self.twitter_media?
      base["twitter_image"] = !!(tweets.find { |tweet| tweet.media? })
      base["twitter_link"] = !!(tweets.find { |tweet| tweet.urls? })
    end
    base
  end

  def public_id_alt
    self.data && self.data["public_id_alt"]
  end

  def processed_image
    if self.image && self.image["original_url"] && self.image["width"] && self.image["height"] && self.image["processed_url"]
      image_url = self.image["processed_url"]
      host = ENV["ENTRY_IMAGE_HOST"]
      url = URI(image_url)
      url.host = host if host
      url.scheme = "https"
      url.to_s
    end
  end

  def processed_image?
    processed_image ? true : false
  end

  def itunes_image
    if self.data && self.data["itunes_image_processed"]
      image_url = self.data["itunes_image_processed"]

      host = ENV["ENTRY_IMAGE_HOST"]

      url = URI(image_url)
      url.host = host if host
      url.scheme = "https"
      url.to_s
    end
  end

  def update_content
    original = self.content
    if self.tweet?
      self.content = ApplicationController.render(template: "entries/_tweet_default.html.erb", locals: {entry: self}, layout: nil)
    end
  rescue
    self.content = original
  end

  def content_diff
    result = nil
    if self.original && self.original["content"].present?
      begin
        before = ContentFormatter.format!(self.original["content"], self)
        after = ContentFormatter.format!(self.content, self)
        result = HTMLDiff::Diff.new("<div>#{before}</div>", "<div>#{after}</div>").inline_html
        result = (result.length > after.length) ? result.html_safe : after.html_safe
      rescue
      end
    end
    result
  end

  private

  def base_url
    parent_feed = self.feed
    if is_fully_qualified(parent_feed.site_url)
      parent_feed.site_url
    else
      parent_feed.feed_url
    end
  end

  def is_fully_qualified(url_string)
    url_string.respond_to?(:start_with?) && url_string.start_with?("http")
  end

  def ensure_published
    now = DateTime.now
    if self.published.nil? || self.published > now || self.published.to_i == 0
      self.published = now
    end
    true
  end

  def cache_public_id
    FeedbinUtils.update_public_id_cache(self.public_id, self.content, self.public_id_alt)
    true
  end

  def mark_as_unread
    if skip_mark_as_unread.blank? && self.published > 1.month.ago
      filters = Hash.new.tap do |hash|
        hash[:feed_id] = self.feed_id
        hash[:active] = true
        hash[:muted] = false
        if self.tweet?
          hash[:show_retweets] = true if self.retweet?
          hash[:media_only] = false if !self.twitter_media?
        end
      end

      subscriptions = Subscription.where(filters).pluck(:user_id)
      unread_entries = subscriptions.each_with_object([]) do |user_id, array|
        array << UnreadEntry.new(user_id: user_id, feed_id: self.feed_id, entry_id: self.id, published: self.published, entry_created_at: self.created_at)
      end
      UnreadEntry.import(unread_entries, validate: false)
    end
    SearchIndexStore.perform_async(self.class.name, self.id)
  end

  def add_to_created_at_set
    score = "%10.6f" % self.created_at.to_f
    key = FeedbinUtils.redis_feed_entries_created_at_key(self.feed_id)
    $redis[:sorted_entries].with do |redis|
      redis.zadd(key, score, self.id)
    end
  end

  def add_to_published_set
    score = "%10.6f" % self.published.to_f
    key = FeedbinUtils.redis_feed_entries_published_key(self.feed_id)
    $redis[:sorted_entries].with do |redis|
      redis.zadd(key, score, self.id)
    end
  end

  def increment_feed_stat
    result = FeedStat.where(feed_id: self.feed_id, day: self.published).update_all("entries_count = entries_count + 1")
    if result == 0
      FeedStat.create(feed_id: self.feed_id, day: self.published, entries_count: 1)
    end
  end

  def create_summary
    if self.tweet?
      begin
        self.summary = self.tweet_summary
      rescue
        self.summary = ""
      end
    else
      self.summary = ContentFormatter.summary(self.content, 256)
    end
  end

  def touch_feed_last_published_entry
    last_published_entry = self.feed.last_published_entry
    if last_published_entry.nil? || last_published_entry < self.published
      self.feed.last_published_entry = published
      feed.save
    end
  end

  def find_images
    EntryImage.perform_async(self.id)
    if self.data && self.data["itunes_image"]
      ItunesImage.perform_async(self.id, self.data["itunes_image"])
    end
  end

  def save_pages
    if self.tweet?
      cached = SavePages.new().perform(self.id, false)
      if cached
        Librato.increment "readability.cached"
      else
        SavePages.perform_async(self.id)
      end
    end
  end
end
