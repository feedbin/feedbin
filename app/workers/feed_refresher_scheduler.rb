require 'sidekiq/api'
require_relative '../../lib/batch_jobs'

class FeedRefresherScheduler
  include Sidekiq::Worker
  include BatchJobs
  sidekiq_options queue: :critical

  STRATEGY_KEY = "last_refresh:strategy".freeze

  def perform
    refresh_feeds if refresh_queue_empty?
  end

  def refresh_feeds
    feed = Feed.last
    if feed
      jobs = job_args(feed.id, priority?)
      set_strategy
      Sidekiq::Client.push_bulk(
        'args'  => jobs,
        'class' => "FeedRefresher",
        'queue' => 'worker_slow_critical'
      )
    end
    Librato.increment 'refresh_feeds'
  end

  def priority?
    last_refresh_strategy = Sidekiq.redis {|client| client.get(STRATEGY_KEY)}
    if last_refresh_strategy.blank? || last_refresh_strategy == 'all'
      true
    else
      false
    end
  end

  def set_strategy
    if priority?
      Sidekiq.redis {|client| client.set(STRATEGY_KEY, "partial")}
    else
      Sidekiq.redis {|client| client.set(STRATEGY_KEY, "all")}
    end
  end

  def refresh_queue_empty?
    queues = Sidekiq::Stats.new().queues
    queues['feed_refresher_fetcher'].blank? || queues['feed_refresher_fetcher'] == 0
  end

end
