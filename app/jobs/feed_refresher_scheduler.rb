require 'sidekiq/api'
require_relative '../../lib/batch_jobs'

class FeedRefresherScheduler
  include Sidekiq::Worker
  include BatchJobs
  sidekiq_options queue: :worker_slow_critical

  COUNT_KEY = "feed_refresher_scheduler:count".freeze

  def perform
    if queue_empty?('feed_refresher_receiver') && queue_empty?('feed_refresher_fetcher')
      refresh_feeds
    end
  end

  def refresh_feeds
    feed = Feed.last
    if feed
      jobs = job_args(feed.id, priority?, force_refresh?)
      Sidekiq::Client.push_bulk(
        'args'  => jobs,
        'class' => "FeedRefresher",
        'queue' => 'worker_slow_critical'
      )
      increment
    end
  end

  def priority?
    @priority ||= count % 2 == 0
  end

  def force_refresh?
    @force_refresh ||= count % 2 != 0 && count % 3 == 0
  end

  def increment
    Librato.increment 'refresh_feeds'
    Sidekiq.redis {|client| client.incr(COUNT_KEY)}
  end

  def count
    @count ||= begin
      result = Sidekiq.redis {|client| client.get(COUNT_KEY)} || 0
      result.to_i
    end
  end

  def queue_empty?(queue)
    @queues ||= Sidekiq::Stats.new().queues
    @queues[queue].blank? || @queues[queue] == 0
  end

end
