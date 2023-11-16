class Entry < ApplicationRecord
  include Searchable

  attr_accessor :fully_qualified_url, :read, :starred, :skip_mark_as_unread, :skip_recent_post_check

  store :settings, accessors: [:archived_images, :media_image, :newsletter, :newsletter_from, :embed_duration], coder: JSON

  enum provider: [:twitter, :youtube], _prefix: true

  belongs_to :feed
  has_many :unread_entries, dependent: :delete_all
  has_many :starred_entries
  has_many :recently_read_entries

  before_create :ensure_published
  before_create :create_summary
  before_create :update_content
  before_create :provider_metadata

  before_update :create_summary

  after_commit :cache_public_id, on: [:create, :update]
  after_commit :find_images, on: :create, unless: :skip_images?
  after_commit :mark_as_unread, on: :create
  after_commit :mark_as_unplayed, on: :create
  after_commit :increment_feed_stat, on: :create
  after_commit :touch_feed_last_published_entry, on: :create
  after_commit :harvest_links, on: :create
  after_commit :harvest_embeds, on: [:create, :update]
  after_commit :cache_views, on: [:create, :update]
  after_commit :search_index_store_update, on: [:update]

  validate :has_content
  validates :feed, :public_id, presence: true

  self.per_page = 100

  def self.entries_with_feed(entry_ids, sort)
    in_order_of(:id, entry_ids).includes(feed: [:favicon])
  end

  def self.entries_list
    select(:id, :feed_id, :title, :summary, :published, :image, :data, :author, :url, :updated_at, :settings)
  end

  def self.sort_preference(sort)
    if sort == "ASC"
      order("published ASC")
    else
      order("published DESC")
    end
  end

  def newsletter?
    feed.newsletter?
  end

  def youtube?
    data && data["youtube_video_id"].present?
  end

  def podcast?
    data && ["audio/mp3", "audio/mpeg"].include?(data["enclosure_type"])
  end

  def tweet?
    tweet.present?
  end

  def micropost?
    micropost.present?
  end

  def author
    return self[:author] unless self[:author].nil?
    return if json_feed.nil?

    authors = json_feed.safe_dig("authors")
    return authors unless authors.respond_to?(:filter_map)
    authors = authors.filter_map { _1&.safe_dig("name") }
    authors.to_sentence
  rescue
    nil
  end

  def fully_qualified_url
    return nil if url.blank? || !url.respond_to?(:strip)
    return url.strip if url.strip.downcase.start_with?("http")
    return url if feed.pages?

    result = feed.site_relative_url(url)
    if result.blank?
      result = feed.feed_relative_url(url)
    end
    result
  end

  def rebase_url(original_url)
    return nil if original_url.nil?
    return original_url.strip if original_url.strip.downcase.start_with?("http")
    return nil if fully_qualified_url.nil?

    base = Addressable::URI.heuristic_parse(fully_qualified_url)
    original_url = Addressable::URI.heuristic_parse(original_url)
    Addressable::URI.join(base, original_url)
  rescue Addressable::URI::InvalidURIError
    Rails.logger.error("Invalid uri original_url=#{original_url} fully_qualified_url=#{fully_qualified_url}")
    nil
  end

  def base_url
    feed.pages? ? url : feed.site_url
  end

  def processed_image
    if image && image["original_url"] && image["width"] && image["height"] && image["processed_url"]
      image_url = image["processed_url"]
      host = ENV["ENTRY_IMAGE_HOST"]
      url = URI(image_url)
      url.host = host if host
      url.scheme = "https"
      url.to_s
    end
  end

  def placeholder_color
    if image && image["placeholder_color"].respond_to?(:length) && image["placeholder_color"].length == 6
      image["placeholder_color"]
    end
  end

  def processed_image?
    processed_image ? true : false
  end

  def itunes_image
    if media_image || (data && data["itunes_image_processed"])
      image_url = media_image || data["itunes_image_processed"]

      host = ENV["ENTRY_IMAGE_HOST"]

      url = URI(image_url)
      url.host = host if host
      url.scheme = "https"
      url.to_s
    end
  end

  def content_diff
    @content_diff ||= begin
      result = nil
      if content && original && original["content"].present? && original["content"].length != content.length
        begin
          before = ContentFormatter.format!(original["content"], self)
          after = ContentFormatter.format!(content, self)
          result = HTMLDiff::Diff.new("<div>#{before}</div>", "<div>#{after}</div>").inline_html
          result = result.html_safe
        rescue
        end
      end
      result
    end
  end

  def audio_duration
    seconds = 0
    duration = data && data["itunes_duration"]

    return seconds if duration.nil?

    parts = duration.to_s.split(":").map(&:to_i).compact
    parts.first(3).reverse.each_with_index do |item, index|
      seconds += item * 60 ** index
    end
    seconds
  end

  def media_duration
    duration = embed_duration || audio_duration
    return nil if duration == 0
    duration
  end

  def media
    items = data&.safe_dig("media").respond_to?(:each) && data&.safe_dig("media") || []
    items.filter_map do |item|
      next unless item.respond_to?(:dig)
      url = item.safe_dig("url")
      type = item.safe_dig("type")
      next unless url.present? && type.present?
      next unless url.start_with?("http")
      OpenStruct.new(url: url, type: type)
    end
  end

  def micropost
    @micropost ||= begin
      if data.respond_to?(:has_key?)
        post = Micropost.new(self.data, title, feed: feed)
        post.valid? ? post : nil
      end
    end
  end

  def archived_images?
    !!archived_images
  end

  def newsletter_url
    URI::HTTPS.build(
      host: ENV["NEWSLETTER_HOST"],
      path: "/#{public_id[0..2]}/#{public_id}.html"
    ).to_s
  end

  def extracted_content_url
    MercuryParser.new(fully_qualified_url).service_url rescue nil
  end

  def hostname
    URI(url).host
  rescue
    nil
  end

  def content_format
    data && data["format"] || "default"
  end

  def search_data
    SearchData.new(self).to_h
  end

  def public_id_alt
    data && data["public_id_alt"]
  end

  def published_recently?
    published > 7.days.ago
  end

  def thread
    data&.safe_dig("thread") || []
  end

  def twitter_thread_ids
    thread.map do |t|
      t.safe_dig("id")
    end
  end

  def tweet_thread
    @tweet_thread ||= begin
      thread.map { |part| Twitter::Tweet.new(part.deep_symbolize_keys) }
    end
  rescue
    []
  end

  def twitter_id
    data&.safe_dig("tweet", "id")
  end

  def tweet
    @tweet ||= Tweet.new(data, image) rescue nil
  end

  def json_feed
    data&.respond_to?(:dig) && data&.safe_dig("json_feed")
  end

  def urls
    array = data&.safe_dig("urls")&.map do |url|
      Addressable::URI.heuristic_parse(url)
    end
    array || []
  end

  def link_image
    if data && data["twitter_link_image_processed"]
      image_url = data["twitter_link_image_processed"]

      host = ENV["ENTRY_IMAGE_HOST"]

      url = URI(image_url)
      url.host = host if host
      url.scheme = "https"
      url.to_s
    end
  end

  def link_image_placeholder_color
    if data && data["twitter_link_image_placeholder_color"].respond_to?(:length) && data["twitter_link_image_placeholder_color"].length == 6
      data["twitter_link_image_placeholder_color"]
    end
  end

  def link_preview_url
    if tweet?
      tweet.main_tweet.urls.first.expanded_url.to_s
    elsif micropost?
      urls.first.to_s
    end
  end

  private

  def provider_metadata
    if tweet? && tweet.main_tweet
      self.url = tweet.main_tweet.uri.to_s
      self.main_tweet_id = tweet.main_tweet.id
      self.provider = self.class.providers[:twitter]
      self.provider_id = tweet.main_tweet.id
    elsif youtube?
      self.provider = self.class.providers[:youtube]
      self.provider_id = data["youtube_video_id"]
      if embed = Embed.youtube_video.find_by_provider_id(self.provider_id)
        self.provider_parent_id = embed.parent_id
      end
    end
  end

  def update_content
    original = content
    if tweet?
      self.content = ApplicationController.render(template: "entries/_tweet_default", formats: :html, locals: {entry: self}, layout: nil)
    end
  rescue
    self.content = original
  end

  def has_content
    if [title, url, entry_id, content].compact.count == 0
      errors.add(:base, "entry has no content")
    end
  end

  def ensure_published
    now = Time.now
    if published.nil? || published > now || published.to_i <= 0
      self.published = now
    end
    true
  end

  def cache_public_id
    FeedbinUtils.update_public_id_cache(public_id, content, public_id_alt)
  end

  def mark_as_unread
    if skip_mark_as_unread.blank? && recent_post
      filters = {}.tap do |hash|
        hash[:feed_id] = feed_id
        hash[:active] = true
        hash[:muted] = false
      end

      user_ids = Subscription.where(filters).pluck(:user_id)
      unread_entries = user_ids.each_with_object([]) { |user_id, array|
        array << UnreadEntry.new(user_id: user_id, feed_id: feed_id, entry_id: id, published: published, entry_created_at: created_at)
      }
      UnreadEntry.import(unread_entries, validate: false, on_duplicate_key_ignore: true)
    end
    Search::SearchIndexStore.perform_async(self.class.name, id)
  end

  def search_index_store_update
    Search::SearchIndexStore.perform_async(self.class.name, id, true)
  end

  def mark_as_unplayed
    if skip_mark_as_unread.blank? && recent_post
      subscriptions = PodcastSubscription.subscribed.where(feed_id: feed_id)
      entries = subscriptions.filter_map do |subscription|
        unless subscription.filtered?([title, data&.safe_dig("itunes_author"), content].join)
          QueuedEntry.new(user_id: subscription.user_id, feed_id: feed_id, entry_id: id, order: Time.now.to_i, progress: 0, duration: audio_duration)
        end
      end
      QueuedEntry.import(entries, validate: false, on_duplicate_key_ignore: true)
      increment!(:queued_entries_count, entries.count)

      notification_ids = PodcastSubscription.where(feed_id: feed_id, status: [:subscribed, :bookmarked]).pluck(:user_id)
      Sidekiq::Client.push_bulk("args" => notification_ids.map {|user_id| [user_id, id]}, "class" => PodcastPushNotification)
    end
  end

  def recent_post
    skip_recent_post_check || published > 1.month.ago
  end

  def increment_feed_stat
    result = FeedStat.where(feed_id: feed_id, day: published).update_all("entries_count = entries_count + 1")
    if result == 0
      FeedStat.create(feed_id: feed_id, day: published, entries_count: 1)
    end
  end

  def create_summary
    if tweet?
      begin
        self.summary = tweet.tweet_summary
      rescue
        self.summary = ""
      end
    else
      self.summary = ContentFormatter.summary(content, 256)
    end
  end

  def touch_feed_last_published_entry
    last_published_entry = feed.last_published_entry
    if last_published_entry.nil? || last_published_entry < published
      feed.last_published_entry = published
      feed.save
    end
  end

  def find_images
    ImageCrawler::EntryImage.perform_async(public_id)
    if data && data["itunes_image"]
      ImageCrawler::ItunesImage.perform_async(public_id)
    end
  end

  def has_embeds?
    return true if youtube?
    return true if micropost?
    return true if content.respond_to?(:include?) && content.include?("iframe")
    return false
  end

  def harvest_embeds
    HarvestEmbeds.perform_async(id) if has_embeds?
  end

  def harvest_links
    HarvestLinks.perform_async(id) if micropost?
  end

  def cache_views
    CacheEntryViews.new.perform(id)
  end

  def skip_images?
    if ENV["SKIP_IMAGES"].present?
      Rails.logger.info("SKIP_IMAGES is present, no images will be processed")
      true
    end
  end
end
