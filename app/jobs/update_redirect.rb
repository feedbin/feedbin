class UpdateRedirect
  include Sidekiq::Worker

  def perform(feed_id, to)
    feed = Feed.find(feed_id)
    feed.update(redirected_to: to, current_feed_url: to)
  end
end
