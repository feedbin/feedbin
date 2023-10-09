class ImportItem < ApplicationRecord
  serialize :details, Hash
  belongs_to :import
  enum status: [:pending, :complete, :failed, :fixable]
  store_accessor :error, :class, :message, prefix: true
  has_many :discovered_feeds, foreign_key: :site_url, primary_key: :site_url
  has_one :favicon, foreign_key: :host, primary_key: :host

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

  def set_site_url
    self.site_url = details[:html_url]
  end

  def host
    self.host = Addressable::URI.heuristic_parse(details[:html_url])&.host&.downcase
  end

  def title
    details[:title]
  end

  def last_published_entry
    nil
  end

  def feed_url
    details[:xml_url]
  end

  def human_error
    return unless failed? || fixable?
    ERRORS[error_class] || "Connection error"
  end

  def replaceable_path
    Rails.application.routes.url_helpers.settings_import_item_path(self)
  end
end
