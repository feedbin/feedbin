class Favicon < ApplicationRecord
  default_scope { select(*(Favicon.column_names - ["favicon"])) }

  validates :url, presence: true

  def data
    self[:data] || {}
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
