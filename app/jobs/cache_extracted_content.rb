class CacheExtractedContent
  include Sidekiq::Worker
  sidekiq_options queue: :low, retry: false

  def perform(entry_id, feed_id)
    sticky_on = Subscription.where(feed_id: feed_id, view_inline: true, active: true).exists?
    if sticky_on
      # entry = Entry.select(:id, :feed_id, :url).find(entry_id)
      # MercuryParser.parse(entry.fully_qualified_url).domain
      Librato.increment "readability.cache_extract"
    end
  rescue ActiveRecord::RecordNotFound
  end

end
