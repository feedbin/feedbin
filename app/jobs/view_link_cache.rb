class ViewLinkCache
  include Sidekiq::Worker
  sidekiq_options queue: :critical, retry: false

  def perform(url, expires_at = nil)
    if !Expires.expired?(expires_at)
      key = FeedbinUtils.page_cache_key(url)
      Rails.cache.fetch(key) do
        MercuryParser.parse(url)
      end
    end
  end
end
