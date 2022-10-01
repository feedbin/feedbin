module WebSub
  class Subscribe
    include Sidekiq::Worker
    sidekiq_options retry: false

    def perform(feed_id)
      feed = Feed.find(feed_id)
      WebSubHelper.subscribe(feed)
    end
  end
end