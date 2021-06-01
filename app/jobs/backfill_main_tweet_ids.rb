class BackfillMainTweetIds
  include Sidekiq::Worker
  sidekiq_options queue: :worker_slow

  def perform(feed_id)
    Entry.where(feed_id: feed_id).update_all("main_tweet_id = COALESCE(data->'tweet'->'retweeted_status'->>'id', data->'tweet'->>'id')")
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
