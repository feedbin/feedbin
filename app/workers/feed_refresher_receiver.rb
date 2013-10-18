class FeedRefresherReceiver
  include Sidekiq::Worker
  sidekiq_options queue: :feed_refresher_receiver

  def perform(update)
    feed = Feed.find(update['feed']['id'])
    if update['entries'].any?
      update['entries'].each do |entry|
        begin
          feed.entries.create!(entry)
        rescue Exception
          Sidekiq.redis { |client| client.hset("entry:public_ids:#{entry['public_id'][0..4]}", entry['public_id'], 1) }
        end
      end
    end
    feed.etag = update['feed']['etag']
    feed.last_modified = update['feed']['last_modified']
    feed.save
  end

end
