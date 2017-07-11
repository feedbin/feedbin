class ViewLinkCache
  include Sidekiq::Worker
  sidekiq_options queue: :critical, retry: false

  def perform(url)
    Rails.cache.fetch("content_view:#{Digest::SHA1.hexdigest(url)}:v5") do
      MercuryParser.parse(url)
    end
  end

end
