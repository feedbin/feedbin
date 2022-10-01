module WebSub
  class Unsubscribe
    include Sidekiq::Worker
    sidekiq_options retry: false

    def perform(feed_id)
      feed = Feed.find(feed_id)
      feed.update(push_expiration: nil)
      WebSubHelper.unsubscribe(feed)
    end
  end
end