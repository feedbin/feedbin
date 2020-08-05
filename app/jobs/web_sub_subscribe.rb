class WebSubSubscribe
  include Sidekiq::Worker
  sidekiq_options retry: false

  def perform(feed_id)
    feed = Feed.find(feed_id)
    WebSub.subscribe(feed)
  end
end
