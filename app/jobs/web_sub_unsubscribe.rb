class WebSubUnsubscribe
  include Sidekiq::Worker
  sidekiq_options retry: false

  def perform(feed_id)
    feed = Feed.find(feed_id)
    feed.update(push_expiration: nil)
    WebSub.unsubscribe(feed)
  end
end
