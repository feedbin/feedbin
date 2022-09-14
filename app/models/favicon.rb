class Favicon < ApplicationRecord
  default_scope { select(*(Favicon.column_names - ["favicon"])) }

  validates :url, presence: true

  after_commit :touch_owners

  def touch_owners
    TouchFeeds.perform_async(host)
  end

  def data
    self[:data] || {}
  end

  def host_class
    "host-#{host}".parameterize
  end

  def cdn_url
    @cdn_url ||= begin
      if url
        uri = URI(url)
        if ENV["FAVICON_HOST"]
          uri.host = ENV["FAVICON_HOST"]
        end
        uri.scheme = "https"
        uri.to_s
      end
    end
  end
end
