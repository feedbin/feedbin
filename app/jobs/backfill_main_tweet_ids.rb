class BackfillMainTweetIds
  include Sidekiq::Worker
  sidekiq_options queue: :worker_slow

  def perform(feed_id)
    feed = Feed.find(feed_id)
    feed.entries.each do |entry|
      entry.update(main_tweet_id: entry.main_tweet.id)
    end
  end

  def schedule
    ids = Feed.twitter.pluck(:id)
    ids = ids.concat(Feed.twitter_home.pluck(:id))
    Sidekiq::Client.push_bulk(
      "args" => ids.map {|id| [id]},
      "class" => self.class.name,
      "queue" => self.class.get_sidekiq_options["queue"].to_s
    )
  end
end
