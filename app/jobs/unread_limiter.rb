class UnreadLimiter
  include Sidekiq::Worker

  def perform(feed_id)
    entry_limit = if ENV["ENTRY_LIMIT"]
      ENV["ENTRY_LIMIT"].to_i
    else
      400
    end

    subscriptions = Subscription.where(feed_id: feed_id).where(active: true)
    subscriptions.each do |subscription|
      ids = UnreadEntry.where(user_id: subscription.user_id, feed_id: subscription.feed_id).order(published: :desc).offset(entry_limit).pluck(:id)
      ids = ids.last(ids.size * 0.05)
      UnreadEntry.where(id: ids).delete_all
    end
  end
end
