class FeedRefresherReceiver
  include Sidekiq::Worker
  sidekiq_options queue: :feed_refresher_receiver

  def perform(update)
    feed = Feed.find(update['feed']['id'])
    if update['entries'].any?
      update['entries'].each do |entry|
        begin
          if entry['update'] == true
            original_entry = Entry.find_by_public_id(entry['public_id'])
            original_entry.update_attributes(updated_content: entry['content'], updated: entry['updated'])
            Librato.increment('entry.update')
          else
            feed.entries.create!(entry)
            Librato.increment('entry.create')
          end
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
