class SelfUrl
  include Sidekiq::Worker
  sidekiq_options retry: false, queue: :worker_slow

  def perform(feed_id = nil, schedule = false)
    return true
    if schedule
      build
    else
      update(feed_id)
    end
  end

  def update(feed_id)
    feed = Feed.find(feed_id)
    request = Feedkit::Feedkit.new.fetch_and_parse(feed.feed_url)
    self_url = request.self_url
    feed.update(self_url: self_url)
  rescue
    feed.update(self_url: feed.feed_url)
  end

  def build
    Feed.select(:id).find_in_batches(batch_size: 10_000) do |feeds|
      Sidekiq::Client.push_bulk(
        "args" => feeds.map { |feed| feed.attributes.values },
        "class" => self.class.name,
        "queue" => "worker_slow",
        "retry" => false,
      )
    end
  end
end
