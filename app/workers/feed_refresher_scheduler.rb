class FeedRefresherScheduler
  include Sidekiq::Worker

  def perform
    Feed.select(:id, :feed_url, :etag, :last_modified, :subscriptions_count).where("EXISTS (SELECT 1 FROM subscriptions WHERE subscriptions.feed_id = feeds.id AND subscriptions.active = 't')").find_in_batches(batch_size: 5000) do |feeds|
      Sidekiq::Client.push_bulk(
        'args'  => feeds.map{ |feed| feed.attributes.values },
        'class' => 'FeedRefresherFetcher',
        'queue' => 'feed_refresher_fetcher',
        'retry' => false
      )
    end
  end

end
