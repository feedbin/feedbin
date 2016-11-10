class Favicon < ApplicationRecord
  def data
    self[:data] || {}
  end

  def cdn_url
    @cdn_url ||= begin
      uri = URI(self.url)
      if ENV['FAVICON_HOST']
        uri.host = ENV['FAVICON_HOST']
      end
      uri.scheme = 'https'
      uri.to_s
    end
  end
end
