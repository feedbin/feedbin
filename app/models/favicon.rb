class Favicon < ApplicationRecord
  default_scope { select(*(Favicon.column_names - ["favicon"])) }

  validates :url, presence: true

  # Pages entries are looked up by the entry's own host rather than the feed's,
  # so there is no association to preload. Resolve the whole collection in one
  # query instead of one per rendered row.
  def self.for_entries(entries)
    hosts = Array(entries).filter_map { _1.hostname if _1.feed&.pages? }.uniq
    return {} if hosts.empty?
    where(host: hosts).index_by(&:host)
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
