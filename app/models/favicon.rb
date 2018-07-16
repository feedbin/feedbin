class Favicon < ApplicationRecord

  default_scope { select(*(Favicon.column_names - ["favicon"])) }

  def data
    self[:data] || {}
  end

  def cdn_url
    @cdn_url ||= begin
      if self.url
        uri = URI(self.url)
        if ENV['AWS_S3_BUCKET_FAVICONS'] && ENV['FAVICON_HOST_NEW'] && uri.host.include?(ENV['AWS_S3_BUCKET_FAVICONS'])
          uri.host = ENV["FAVICON_HOST_NEW"]
        elsif ENV['FAVICON_HOST']
          uri.host = ENV['FAVICON_HOST']
        end
        uri.scheme = 'https'
        uri.to_s
      else
        nil
      end
    end
  end
end
