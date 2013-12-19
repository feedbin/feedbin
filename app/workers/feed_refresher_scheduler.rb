class FeedRefresherScheduler
  include Sidekiq::Worker

  def perform
    queues = Sidekiq::Stats.new().queues
    if queues['feed_refresher_fetcher'].blank? || queues['feed_refresher_fetcher'] == 0
      refresh_feeds
      Librato.increment 'refresh_feeds'
    end
  end

  def refresh_feeds
    feeds = Feed.select(:id, :feed_url, :etag, :last_modified, :subscriptions_count, :push_expiration).where("EXISTS (SELECT 1 FROM subscriptions WHERE subscriptions.feed_id = feeds.id AND subscriptions.active = 't')")
    last_refresh_strategy = Sidekiq.redis {|client| client.get('last_refresh:strategy')}
    if last_refresh_strategy.blank? || last_refresh_strategy == 'all'
      feeds = feeds.where('feeds.subscriptions_count > 1')
      Sidekiq.redis {|client| client.set('last_refresh:strategy', 'partial')}
    else
      Sidekiq.redis {|client| client.set('last_refresh:strategy', 'all')}
    end

    feeds.find_in_batches(batch_size: 5000) do |feeds|
      arguments = feeds.map do |feed|
        values = feed.attributes.values
        values.pop
        if feed.push_expiration.nil? || feed.push_expiration < Time.now
          values.push(nil) # Placeholder for the body upon fat notifications.
          values.push(Push::callback_url(feed))
          values.push(Push::hub_secret(feed.id))
        end
        values
      end
      queue_refresh(arguments)
    end

  end

  def queue_refresh(arguments)
    Sidekiq::Client.push_bulk(
      'args'  => arguments,
      'class' => 'FeedRefresherFetcher',
      'queue' => 'feed_refresher_fetcher',
      'retry' => false
    )
  end

end
