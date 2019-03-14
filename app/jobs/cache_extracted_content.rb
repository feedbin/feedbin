class CacheExtractedContent
  include Sidekiq::Worker

  def perform(entry_id, feed_id)
    sticky_on = Subscription.where(feed_id: feed_id, view_inline: true, active: true).exists?
    if sticky_on
      Librato.increment "readability.cache_extract"
    end
  end
end
