class Feed < ApplicationRecord
  include YoutubeChannel

  has_many :subscriptions
  has_many :podcast_subscriptions
  has_many :entries
  has_many :users, through: :subscriptions
  has_many :unread_entries
  has_many :starred_entries
  has_many :feed_stats
  has_many :discovered_feeds, -> (feed) { where.not(feed_url: feed.feed_url) }, foreign_key: :site_url, primary_key: :site_url

  has_many :taggings
  has_many :tags, through: :taggings

  has_one :newsletter_sender
  has_one :icon_image_record, -> { provider_feed_icon }, class_name: "Image", foreign_key: :provider_id
  # The host's favicon row, shared by every feed on the host. Keyed by host
  # the way channel_image_record is keyed by channel_id.
  has_one :favicon_image_record, -> { provider_website_favicon }, class_name: "Image", foreign_key: :provider_id, primary_key: :host

  # Everything FaviconComponent (via #icon_url and #site_favicon) can read when
  # rendering this feed's icon. Preload these wherever feeds render in a list,
  # or the icon lookups become a query per feed.
  ICON_PRELOADS = [:favicon_image_record, :icon_image_record, :channel_image_record].freeze

  before_create :set_host
  after_create :refresh_favicon

  after_commit :web_sub_subscribe, on: :create

  attribute :crawl_data, CrawlDataType.new
  attr_accessor :count, :tags
  attr_readonly :feed_url

  after_initialize :default_values

  enum :feed_type, {xml: 0, newsletter: 1, twitter: 2, twitter_home: 3, pages: 4}

  store :settings, accessors: [:custom_icon, :current_feed_url, :custom_icon_format, :meta_title, :meta_description, :meta_crawled_at], coder: JsonConverter

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
    names = names.split(",") if names.is_a?(String)
    names.map do |name|
      name = name.strip
      unless name.blank?
        tag = Tag.where(name: name.strip).first_or_create!
        taggings << self.taggings.where(user: user, tag: tag).first_or_create!
      end
    end
    taggings
  end

  def icon_options
    items = {}
    items[custom_icon] = "round" unless options.safe_dig("itunes_image")
    if custom_icon_format == "round"
      items[options.safe_dig("image", "url")] = "square"
    end
    items[options.safe_dig("json_feed", "icon")] = "square"
    items[options.safe_dig("json_feed", "author", "avatar")] = "round"
    items
  end

  def icon
    base = icon_options.keys.find { !it.nil? }
    return nil if base.nil?
    feed_relative_url(base)
  end

  # A podcast's artwork is square whatever else the feed offers. That used
  # to follow from the legacy custom_icon entry in icon_options; the entry
  # is gone, so the shape comes from the feed being a podcast. Without this
  # every show renders in the round frame FaviconComponent defaults to.
  def default_icon_format
    return "square" if options.safe_dig("itunes_image")

    base = icon_options.keys.find { !it.nil? }
    return nil if base.nil?
    icon_options[base]
  end

  # The renderable URL: images row from our CDN, else the legacy url through
  # the signing proxy. The feed's own row outranks the shared channel row.
  # icon/icon_options/default_icon_format still answer the separate question
  # "which source won and what shape is it".
  def icon_url
    Image.unified_url(icon_image_record&.storage_path) ||
      Image.unified_url(channel_image_record&.storage_path) ||
      (icon && RemoteFile.signed_url(icon))
  end

  # The frame for this feed's icon, from the kind of the row icon_url
  # serves, in the same order. nil when no row exists, which is also when
  # icon_url has no row to serve.
  def icon_format
    (icon_image_record || channel_image_record)&.icon_format
  end

  # A feed whose entries carry no titles: a stream of posts rather than
  # articles. The parser tests the same condition on the parsed entries; the
  # stored ones exist by the time the icon crawler asks.
  #
  # Feed's own after_create enqueues ImageCrawler::FeedIcon before
  # create_from_parsed_feed has stored the feed's entries, so a worker that
  # wins that race sees no entries and this returns false even for a
  # micropost feed. Subscription's after_create enqueues the same crawler
  # again, and by then the entries are stored, so that later run is what
  # recovers the right answer.
  def micropost?
    entries.exists? && !entries.where.not(title: [nil, ""]).exists?
  end

  # The favicon to render for this host, or nil.
  def site_favicon
    favicon_image_record
  end

  def self.create_from_parsed_feed(parsed_feed)
    record = parsed_feed.to_feed
    create_with(record).create_or_find_by!(feed_url: record[:feed_url]).tap do |new_feed|
      parsed_feed.entries.each do |parsed_entry|
        entry_hash = parsed_entry.to_entry
        new_feed.entries.create_with(entry_hash).create_or_find_by(public_id: entry_hash[:public_id])
      end
      # for micropost feeds
      if parsed_feed.entries.filter_map(&:title).blank?
        new_feed.update!(custom_icon_format: "round")
      end
    end
  end

  def check
    Feedkit::Request.download(feed_url)
  end

  def volume
    FeedStat.daily_counts(feed_ids: [id])
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
    self.host = Addressable::URI.heuristic_parse(site_url)&.host&.downcase
  rescue
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
      return
    else
      FeedCrawler::DownloaderCritical.perform_async(id, feed_url, subscriptions_count, crawl_data.to_h)
      Search::FeedMetadataFinder.perform_async(id)
    end
  end

  def list_unsubscribe
    options.safe_dig("email_headers", "List-Unsubscribe")
  end

  def json_feed
    options&.respond_to?(:dig) && options&.safe_dig("json_feed")
  end

  def has_subscribers?
    subscriptions_count > 0
  end

  def web_sub_secret
    Digest::SHA256.hexdigest([id, Rails.application.secret_key_base].join("-"))
  end

  def web_sub_callback(debug: false)
    uri = URI(ENV["PUSH_URL"])
    signature = OpenSSL::HMAC.hexdigest("sha256", web_sub_secret, id.to_s)
    params = {}
    params[:debug] = true if debug
    Rails.application.routes.url_helpers.web_sub_verify_url(id, web_sub_callback_signature, protocol: uri.scheme, host: uri.host, params: params)
  end

  def web_sub_callback_signature
    OpenSSL::HMAC.hexdigest("sha256", web_sub_secret, id.to_s)
  end

  def web_sub_subscribe
    WebSub::Subscribe.perform_async(id)
  end

  def hubs
    if self[:hubs].blank? && !known_hubs.blank?
      known_hubs
    else
      self[:hubs]
    end
  end

  def redirect_key
    "refresher_redirect_stable_%d" % id
  end

  def site_url
    feed_relative_url(self[:site_url])
  end

  def feed_relative_url(url)
    root = crawl_data&.redirected_to || feed_url
    rebase_url(root, url).to_s
  end

  def site_relative_url(url)
    root = site_url
    rebase_url(root, url).to_s
  end

  def rebase_url(root, relative)
    return root if relative.blank? || !relative.respond_to?(:strip)
    return relative.strip if relative.strip.downcase.start_with?("http")
    return nil if root.blank?

    # The root may be stored without a scheme, so it gets the heuristic
    # parser. The relative part must not: heuristic_parse reads a plain
    # "icon.png" as a host and the join then yields http://icon.png.
    root = Addressable::URI.heuristic_parse(root)
    relative = Addressable::URI.parse(relative.strip)
    Addressable::URI.join(root, relative)
  rescue Addressable::URI::InvalidURIError
    Rails.logger.error("Invalid uri feed=#{id} root=#{root} relative=#{relative}")
    nil
  end

  def sourceable
    Sourceable.new(
      type: self.class.name,
      id: id,
      title: title,
      section: "Feeds",
      jumpable: true
    )
  end

  def fixable_error?
    return false unless crawl_error?

    irrecoverable_errors = [
      "Feedkit::ConnectionError",
      "Feedkit::SSLError",
      "Feedkit::TimeoutError"
    ]
    return false if irrecoverable_errors.include?(crawl_data.last_error.safe_dig("class"))
    return true
  end

  def crawl_error?
    crawl_data.respond_to?(:error_count) && crawl_data.error_count > 23
  end

  def crawl_error_message
    message = CrawlingError.message(crawl_data.last_error.safe_dig("class"))
    date = Time.at(crawl_data.downloaded_at) rescue nil
    if date.present? && date != Time.at(0)
      message = "#{date.to_formatted_s(:date)}: #{message}"
    else
      message = "Error: #{message}"
    end

    message
  end

  def fixable?
    crawl_error? && discovered_feeds.present?
  end

  def dead?
    crawl_error? && !discovered_feeds.present?
  end

  def search_data
    FeedSearchData.new(self).to_h
  end

  def self.search(query)
    FeedSearch.new(query).search
  end

  def feed_description
    options&.safe_dig("description") || meta_description
  end

  def last_download
    if crawl_data.downloaded_at == 0
      nil
    else
      Time.at(crawl_data.downloaded_at)
    end
  rescue
    nil
  end

  private

  def refresh_favicon
    FaviconCrawler::Finder.perform_async(host)
    ImageCrawler::ItunesFeedImage.perform_async(id)
    ImageCrawler::FeedIcon.perform_async(id)
  end

  def default_values
    if respond_to?(:options)
      self.options ||= {}
    end
  end
end
