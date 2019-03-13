class ViewLinkCache
  include Sidekiq::Worker
  sidekiq_options queue: :critical, retry: false

  def perform(url, expires_at = nil)
    unless Expires.expired?(expires_at)
      MercuryParser.parse(url).content
    end
  end
end
