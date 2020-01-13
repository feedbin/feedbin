class UnreadLimiter
  include Sidekiq::Worker

  def perform(feed_id)
    subscriptions = Subscription.where(feed_id: feed_id)
    subscriptions.each do |subscription|
      subscription.user.unread_entries.where(feed_id: feed_id).order(published: :desc).offset(400).delete_all
    end
  end
end
