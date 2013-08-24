class Entry < ActiveRecord::Base  
  
  attr_accessor :fully_qualified_url, :read, :starred, :skip_mark_as_unread
  
  belongs_to :feed
  has_many :unread_entries, dependent: :delete_all
  has_many :starred_entries
  
  before_create :ensure_published
  before_create :cache_public_id
  before_create :create_summary
  after_commit :mark_as_unread, on: :create
  
  validates_uniqueness_of :public_id
    
  def entry=(entry)
    self.author    = entry.author
    self.content   = entry.content
    self.title     = entry.title
    self.url       = entry.url
    self.entry_id  = entry.entry_id

    self.published = entry.try(:published)
    self.updated   = entry.try(:updated)

    self.public_id     = entry._public_id_
    self.old_public_id = entry._old_public_id_
  end  
  
  def self.include_unread_entries(user_id)
    joins("LEFT OUTER JOIN unread_entries ON entries.id = unread_entries.entry_id AND unread_entries.user_id = #{user_id}")
  end
  
  def self.unread_new
    where("unread_entries.entry_id IS NOT NULL")
  end
  
  def self.read_new
    where("unread_entries.entry_id IS NULL")
  end
  
  def self.include_starred_entries(user_id)
    joins("LEFT OUTER JOIN starred_entries ON entries.id = starred_entries.entry_id AND starred_entries.user_id = #{user_id}")
  end
  
  def self.starred_new
    where("starred_entries.entry_id IS NOT NULL")
  end
  
  def self.unstarred_new
    where("starred_entries.entry_id IS NULL")
  end
    
  def cache_key
    additions = []
    if defined?(read) && read
      additions << '/read'
    end
    if defined?(starred) && starred
      additions << '/starred'
    end
    super + additions.join('')
  end
  
  def fully_qualified_url
    entry_url = self.url
    if entry_url
      unless self.url.start_with?('http')
        site_url = self.feed.site_url
        if site_url
          entry_url = URI.join(site_url.gsub('&#38;', '&'), entry_url.gsub('&#38;', '&')).to_s
        end
      end
    else
      entry_url = self.feed.site_url
    end
    entry_url = entry_url.gsub('&#38;', '&')
    entry_url = Addressable::URI.unescape(entry_url)
    Addressable::URI.escape(entry_url)
  rescue
    self.feed.site_url
  end

  private
  
  def ensure_published
    if self[:published].nil?
      self[:published] = DateTime.now
    end
  end
  
  def cache_public_id
    Sidekiq.redis { |client| client.hset("entry:public_ids:#{self.public_id[0..4]}", self.public_id, 1) }
  end
  
  def mark_as_unread
    unless skip_mark_as_unread
      unread_entries = []
      user_ids = Subscription.where(feed_id: self.feed_id).pluck(:user_id)
      user_ids.each do |user_id|
        unread_entries << UnreadEntry.new(user_id: user_id, feed_id: self.feed_id, entry_id: self.id, published: self.published, entry_created_at: self.created_at)
      end
      UnreadEntry.import(unread_entries, validate: false)
    end
  end
  
  def create_summary
    self.summary = ContentFormatter.summary(self.content)
  end
  
end
