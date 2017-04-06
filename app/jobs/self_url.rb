class SelfUrl
  include Sidekiq::Worker
  sidekiq_options retry: false, queue: :worker_slow

  def perform(feed_id = nil, schedule = false)
    if schedule
      build
    else
      update(feed_id)
    end
  end

  def update(feed_id)
    feed = Feed.find(feed_id)
    request = FeedRequest.new(url: feed.feed_url)
    parsed_feed = ParsedFeed.new(request.body, request)
    if parsed_feed.self_url
      feed.update_attributes(self_url: parsed_feed.self_url)
    end
  end

  def build
    Feed.select(:id).find_in_batches(batch_size: 10_000) do |feeds|
      Sidekiq::Client.push_bulk(
        'args'  => feeds.map{ |feed| feed.attributes.values },
        'class' => self.class.name,
        'queue' => 'worker_slow',
        'retry' => false
      )
    end
  end


end