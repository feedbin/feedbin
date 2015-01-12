class Entry < ActiveRecord::Base
  include Tire::Model::Search

  attr_accessor :fully_qualified_url, :read, :starred, :skip_mark_as_unread

  belongs_to :feed
  has_many :unread_entries, dependent: :delete_all
  has_many :starred_entries
  has_many :recently_read_entries

  before_create :ensure_published
  before_create :cache_public_id, unless: -> { Rails.env.test? }
  before_create :create_summary
  before_update :create_summary
  after_commit :mark_as_unread, on: :create
  after_commit :add_to_created_at_set, on: :create
  after_commit :add_to_published_set, on: :create
  after_commit :increment_feed_stat, on: :create
  after_commit :touch_feed_last_published_entry, on: :create

  tire_settings = {
    analysis: {
      filter: {
        url_stop: {
          "type" => "stop",
          "stopwords" => ["http", "https"]
        },
        url_ngram: {
          "type"     => "nGram",
          "max_gram" => 5,
          "min_gram" => 3
        }
      },
      analyzer: {
        url_analyzer: {
          "tokenizer" => "lowercase",
          "filter"    => ["stop", "url_stop", "url_ngram"],
          "type"      => "custom"
        }
      }
    }
  }

  tire.settings tire_settings do
    tire.mapping do
      indexes :id,        index: :not_analyzed
      indexes :title,     analyzer: 'snowball', boost: 100
      indexes :content,   analyzer: 'snowball'
      indexes :author,    analyzer: 'keyword'
      indexes :url,       as: -> entry { entry.fully_qualified_url }, analyzer: 'url_analyzer'
      indexes :feed_id,   index: :not_analyzed, include_in_all: false
      indexes :published, type: 'date', include_in_all: false
      indexes :updated,   type: 'date', include_in_all: false
    end
  end

  def self.search(params, user)
    params = build_search(params)
    search_options = {
      page: params[:page],
      per_page: WillPaginate.per_page
    }
    unless params[:load] == false
      search_options[:load] = { include: :feed }
    end

    tire.search(search_options) do
      fields ['id']
      query { string params[:query], default_operator: "AND" } if params[:query].present?
      ids = []

      if params[:read] == false
        ids << user.unread_entries.pluck(:entry_id)
      elsif params[:read] == true
        filter :not, { ids: { values: user.unread_entries.pluck(:entry_id) } }
      end

      if params[:size].present?
        size params[:size]
      end

      if params[:starred] == true
        ids << user.starred_entries.pluck(:entry_id)
      elsif params[:starred] == false
        filter :not, { ids: { values: user.starred_entries.pluck(:entry_id) } }
      end

      if params[:sort]
        if %w{desc asc}.include?(params[:sort])
          sort { by :published, params[:sort] }
        end
      else
        sort { by :published, "desc" }
      end

      if ids.any?
        ids = ids.inject(:&) # intersect
        filter :ids, values: ids
      end

      # Always limit searches to subscriptions and starred items
      filter :or, { terms: { feed_id: user.subscriptions.pluck(:feed_id) } },
                  { ids: { values: user.starred_entries.pluck(:entry_id) } }
    end

  end

  def self.build_search(params)
    unread_regex = /(?<=\s|^)is:\s*unread(?=\s|$)/
    read_regex = /(?<=\s|^)is:\s*read(?=\s|$)/
    starred_regex = /(?<=\s|^)is:\s*starred(?=\s|$)/
    unstarred_regex = /(?<=\s|^)is:\s*unstarred(?=\s|$)/
    sort_regex = /(?<=\s|^)sort:\s*(asc|desc|relevance)(?=\s|$)/i

    if params[:query] =~ unread_regex
      params[:query] = params[:query].gsub(unread_regex, '')
      params[:read] = false
    elsif params[:query] =~ read_regex
      params[:query] = params[:query].gsub(read_regex, '')
      params[:read] = true
    end

    if params[:query] =~ starred_regex
      params[:query] = params[:query].gsub(starred_regex, '')
      params[:starred] = true
    elsif params[:query] =~ unstarred_regex
      params[:query] = params[:query].gsub(unstarred_regex, '')
      params[:starred] = false
    end

    if params[:query] =~ sort_regex
      params[:sort] = params[:query].match(sort_regex)[1].downcase
      params[:query] = params[:query].gsub(sort_regex, '')
    end

    params[:query] = escape_search(params[:query])

    params
  end

  def self.escape_search(query)
    if query.present? && query.respond_to?(:gsub)
      special_characters_regex = /([\+\-\!\{\}\[\]\^\~\?\\])/
      escape = '\ '.sub(' ', '')
      query = query.gsub(special_characters_regex) { |character| escape + character }

      colon_regex = /(?<!title|feed_id|body|author):(?=.*)/
      query = query.gsub(colon_regex, '\:')
      query
    end
  end


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

    if entry.try(:_data_)
      self.data = entry._data_
    end
  end

  def self.entries_with_feed(entry_ids, sort)
    entry_ids = entry_ids.map(&:entry_id)
    entries = Entry.where(id: entry_ids).includes(:feed)
    if sort == 'ASC'
      entries = entries.order('published ASC')
    else
      entries = entries.order('published DESC')
    end
    entries
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

  def self.starred_new
    where("starred_entries.entry_id IS NOT NULL")
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

  def self.from_id_cache(user_id, page)
    user = User.find(user_id)

    if page
      page = page.to_i
    else
      page = 1
    end

    start = (page - 1) * WillPaginate.per_page
    stop = start + WillPaginate.per_page - 1

    cache_key = FeedbinUtils.redis_user_entries_published_key(user_id)
    key_exists, entry_ids = $redis.multi do
      $redis.exists(cache_key)
      $redis.zrevrange(cache_key, start, stop)
    end

    if !key_exists

      feed_ids = user.subscriptions.pluck(:feed_id)

      keys = feed_ids.map do |feed_id|
        FeedbinUtils.redis_feed_entries_published_key(feed_id)
      end

      count, expire, entry_ids = $redis.multi do
        $redis.zunionstore(cache_key, keys)
        $redis.expire(cache_key, 2.minutes.to_i)
        $redis.zrevrange(cache_key, start, stop)
      end

    end
    where(id: entry_ids)
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
    if self.published.nil? || self.published > 1.day.from_now
      self.published = DateTime.now
    end
  end

  def cache_public_id
    FeedbinUtils.update_public_id_cache(self.public_id, self.content)
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
    $redis.zadd(key, score, self.id)
  end

  def add_to_published_set
    score = "%10.6f" % self.published.to_f
    key = FeedbinUtils.redis_feed_entries_published_key(self.feed_id)
    $redis.zadd(key, score, self.id)
  end

  def increment_feed_stat
    result = FeedStat.where(feed_id: self.feed_id, day: self.published).update_all("entries_count = entries_count + 1")
    if result == 0
      FeedStat.create(feed_id: self.feed_id, day: self.published, entries_count: 1)
    end
  end

  def create_summary
    self.summary = ContentFormatter.summary(self.content)
  end

  def touch_feed_last_published_entry
    last_published_entry = self.feed.last_published_entry
    if last_published_entry.nil? || last_published_entry < self.published
      self.feed.last_published_entry = published
      feed.save
    end
  end

end
