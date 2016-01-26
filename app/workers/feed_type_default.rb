require_relative '../../lib/batch_jobs'

class FeedTypeDefault
  include Sidekiq::Worker
  include BatchJobs
  sidekiq_options queue: :worker_slow

  def perform(batch)
    feed_ids = build_ids(batch)
    Feed.where(id: feed_ids).update_all(feed_type: Feed.feed_types[:xml])
  end
end
