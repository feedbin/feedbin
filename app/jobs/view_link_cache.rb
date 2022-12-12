class ViewLinkCache
  include Sidekiq::Worker
  sidekiq_options queue: :network_default, retry: false

  def perform(url, expires_at = nil)
    MercuryParser.parse(url).content unless Expires.expired?(expires_at)
  rescue HTTP::TimeoutError, HTTP::ConnectionError
    true
  end
end
