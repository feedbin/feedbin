class ImportItem < ApplicationRecord
  serialize :details, Hash
  belongs_to :import
  enum status: [:pending, :complete, :failed]
  store_accessor :error, :class, :message, prefix: true

  after_commit :import_feed, on: :create

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

  def host
    URI.parse(details[:html_url])&.host rescue nil
  end

  def human_error
    return unless failed?
    ERRORS[error_class] || "Connection error"
  end
end
