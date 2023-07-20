class FeedUpdate
  include Sidekiq::Worker
  sidekiq_options queue: :utility

  def perform(feed_id)
    byebug
    feed = Feed.find(feed_id)
    parsed_url = Feedkit::BasicAuth.parse(feed.feed_url)
    url = feed.current_feed_url ? feed.current_feed_url : parsed_url.url
    response = Feedkit::Request.download(url,
      username: parsed_url.username,
      password: parsed_url.password,
    )
    result = response.parse(original_url: feed.feed_url)
    feed_data = result.to_feed.compact_blank
    feed.update(feed_data)

    entries = result.entries.map do |entry|
      entry.to_entry.tap do |hash|
        hash[:feed_id] = feed_id
      end
    end

    Entry.import!(entries, on_duplicate_key_update: {conflict_target: :public_id, columns: [:title, :url, :author, :content, :data]})
  rescue Feedkit::NotFeed
  end
end
