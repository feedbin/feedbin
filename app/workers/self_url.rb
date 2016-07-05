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
    args = (1..Feed.count).to_a.map { |id| [id] }
    if args.present?
      Sidekiq::Client.push_bulk(
        'args'  => args,
        'class' => self.class.name,
        'queue' => 'worker_slow'
      )
    end
  end


end