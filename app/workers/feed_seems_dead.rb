class FeedSeemsDead
  include Sidekiq::Worker
  sidekiq_options queue: :feed_seems_to_be_dead

  def perform(feed_id)
    feed = Feed.find(feed_id)
    feed.update(alive: false)
  end
end
