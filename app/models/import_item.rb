class ImportItem < ApplicationRecord
  serialize :details, type: Hash
  belongs_to :import
  enum :status, [:pending, :complete, :failed, :fixable]
  store_accessor :error, :class, :message, prefix: true
  has_many :discovered_feeds, foreign_key: :site_url, primary_key: :site_url
  has_one :favicon_image_record, -> { provider_website_favicon }, class_name: "Image", foreign_key: :provider_id, primary_key: :host

  after_commit :import_feed, on: :create
  before_create :set_site_url
  before_create :host

  ERRORS = {
    "Addressable::URI::InvalidURIError" => "Invalid URL",
    "Feedkit::ClientError"              => "Connection error",
    "Feedkit::ConnectionError"          => "Connection error",
    "Feedkit::InvalidUrl"               => "Invalid URL",
    "Feedkit::NotFound"                 => "Not found",
    "Feedkit::ServerError"              => "Server error",
    "Feedkit::SSLError"                 => "Server error",
    "Feedkit::TimeoutError"             => "Connection timed out",
    "Feedkit::TooManyRedirects"         => "Server error",
    "Feedkit::Unauthorized"             => "Unauthorized",
    "HTTP::TimeoutError"                => "Connection timed out",
    "NoMethodError"                     => "Server error",
  }

  def import_feed
    FeedImporter.perform_async(id)
  end

  # The favicon to render for this host, or nil. See Feed#site_favicon.
  def site_favicon
    favicon_image_record
  end

  def set_site_url
    self.site_url = details[:html_url]
  end

  def host
    self.host = Addressable::URI.heuristic_parse(details[:html_url])&.host&.downcase
  rescue
  end

  # `text` is the required OPML attribute and `title` is the optional one, so a
  # producer that emits only `text=` leaves details[:title] nil. Opml::Parser
  # already falls back this way for folder names.
  def title
    details[:title].presence || details[:text]
  end

  def last_published_entry
    nil
  end

  def feed_url
    details[:xml_url]
  end

  def crawl_error_message
    return unless failed? || fixable?
    CrawlingError.message(error_class)
  end

  def replaceable_path
    Rails.application.routes.url_helpers.settings_import_item_path(self)
  end
end
