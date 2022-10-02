module WebSub
  class Subscribe
    include Sidekiq::Worker
    sidekiq_options retry: false

    def perform(feed_id)
      feed = Feed.find(feed_id)
      Hub.subscribe(feed)
    end
  end
end