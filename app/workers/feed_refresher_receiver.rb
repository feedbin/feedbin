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
            entry_update = entry.slice('author', 'content', 'title', 'url', 'entry_id', 'published', 'data')
            if original_entry.original.nil?
              entry_update['original'] = {
                'author'    => original_entry.author,
                'content'   => original_entry.content,
                'title'     => original_entry.title,
                'url'       => original_entry.url,
                'entry_id'  => original_entry.entry_id,
                'published' => original_entry.published,
                'data'      => original_entry.data
              }
            end
            original_entry.update_attributes(entry_update)
            Librato.increment('entry.update')
          else
            feed.entries.create!(entry)
            Librato.increment('entry.create')
          end
        rescue Exception
          if entry['content']
            content_length = entry['content'].length
          else
            content_length = 1
          end
          Sidekiq.redis { |client| client.hset("entry:public_ids:#{entry['public_id'][0..4]}", entry['public_id'], content_length) }
        end
      end
    end
    feed.etag = update['feed']['etag']
    feed.last_modified = update['feed']['last_modified']
    feed.save
  end

end
