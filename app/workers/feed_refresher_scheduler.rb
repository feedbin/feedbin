class FeedRefresherScheduler
  include Sidekiq::Worker

  def perform
    Feed.select(:id, :feed_url, :etag, :last_modified, :subscriptions_count, :push_expiration).where("EXISTS (SELECT 1 FROM subscriptions WHERE subscriptions.feed_id = feeds.id AND subscriptions.active = 't')").find_in_batches(batch_size: 5000) do |feeds|
      arguments = feeds.map do |feed|
        values = feed.attributes.values
        values.pop
        if !feed.push_expiration || feed.push_expiration < Time.now
          values.push(nil) # Placeholder for the body upon fat notifications.
          values.push(Rails.application.routes.url_helpers.push_feed_url(feed, :protocol => Feedbin::Application.config.force_ssl ? "https" : "http" , :host => ENV['DEFAULT_URL_OPTIONS_HOST']))
        end
        values
      end
      Sidekiq::Client.push_bulk(
        'args'  => arguments,
        'class' => 'FeedRefresherFetcher',
        'queue' => 'feed_refresher_fetcher',
        'retry' => false
      )
    end
  end

end
