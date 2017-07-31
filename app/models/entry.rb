class Entry < ApplicationRecord
  include Searchable

  attr_accessor :fully_qualified_url, :read, :starred, :skip_mark_as_unread

  belongs_to :feed
  has_many :unread_entries, dependent: :delete_all
  has_many :starred_entries
  has_many :recently_read_entries

  before_create :ensure_published
  before_create :create_summary
  before_update :create_summary
  after_commit :cache_public_id, on: :create
  after_commit :find_images, on: :create
  after_commit :mark_as_unread, on: :create
  after_commit :add_to_created_at_set, on: :create
  after_commit :add_to_published_set, on: :create
  after_commit :increment_feed_stat, on: :create
  after_commit :touch_feed_last_published_entry, on: :create

  validate :has_content
  validates :feed, :public_id, presence: true

  self.per_page = 100

  def has_content
    if [title, url, entry_id, content].compact.count == 0
      errors.add(:base, 'entry has no content')
    end
  end

  def self.entries_with_feed(entry_ids, sort)
    entry_ids = entry_ids.map(&:entry_id)
    entries = Entry.where(id: entry_ids).includes(feed: [:favicon])
    if sort == 'ASC'
      entries = entries.order('published ASC')
    else
      entries = entries.order('published DESC')
    end
    entries
  end

  def self.entries_list
    select(:id, :feed_id, :title, :summary, :published, :image)
  end

  def self.include_unread_entries(user_id)
    joins("LEFT OUTER JOIN unread_entries ON entries.id = unread_entries.entry_id AND unread_entries.user_id = #{user_id.to_i}")
  end

  def self.unread_new
    where('unread_entries.entry_id IS NOT NULL')
  end

  def self.read_new
    where('unread_entries.entry_id IS NULL')
  end

  def self.include_starred_entries(user_id)
    joins("LEFT OUTER JOIN starred_entries ON entries.id = starred_entries.entry_id AND starred_entries.user_id = #{user_id.to_i}")
  end

  def self.unstarred_new
    where("starred_entries.entry_id IS NULL")
  end

  def self.sort_preference(sort)
    if sort == 'ASC'
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

  def as_indexed_json(options={})
    base = as_json(root: false, only: Entry.mappings.to_hash[:entry][:properties].keys)
    base["title"] = format_text(self.title)
    base["content"] = format_text(self.content)
    base["title_exact"] = base["title"]
    base["content_exact"] = base["content"]
    base
  end

  def format_text(text)
    if text.respond_to?(:chars)
      decoder = HTMLEntities.new
      text = decoder.decode(text)
      text = text.chars.select(&:valid_encoding?).join
      begin
        text = Nokogiri::HTML(text).to_xhtml
        text = Nokogiri::HTML(text).text.squish
      rescue
        text = nil
      end
      text
    end
  end

  def public_id_alt
    self.data && self.data["public_id_alt"]
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
    url_string.respond_to?(:start_with?) && url_string.start_with?('http')
  end

  def ensure_published
    now = DateTime.now
    if self.published.nil? || self.published > now
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
      unread_entries = []
      subscriptions = Subscription.where(feed_id: self.feed_id, active: true, muted: false).pluck(:user_id)
      subscriptions.each do |user_id|
        unread_entries << UnreadEntry.new(user_id: user_id, feed_id: self.feed_id, entry_id: self.id, published: self.published, entry_created_at: self.created_at)
      end
      UnreadEntry.import(unread_entries, validate: false)
    end
    SearchIndexStore.perform_async(self.class.name, self.id)
  end

  def add_to_created_at_set
    score = "%10.6f" % self.created_at.to_f
    key = FeedbinUtils.redis_feed_entries_created_at_key(self.feed_id)
    $redis[:sorted_entries].zadd(key, score, self.id)
  end

  def add_to_published_set
    score = "%10.6f" % self.published.to_f
    key = FeedbinUtils.redis_feed_entries_published_key(self.feed_id)
    $redis[:sorted_entries].zadd(key, score, self.id)
  end

  def increment_feed_stat
    result = FeedStat.where(feed_id: self.feed_id, day: self.published).update_all("entries_count = entries_count + 1")
    if result == 0
      FeedStat.create(feed_id: self.feed_id, day: self.published, entries_count: 1)
    end
  end

  def create_summary
    self.summary = ContentFormatter.summary(self.content)
    true
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
  end

end
