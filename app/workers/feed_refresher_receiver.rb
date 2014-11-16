class FeedRefresherReceiver
  include Sidekiq::Worker
  sidekiq_options queue: :feed_refresher_receiver

  def perform(update)
    feed = Feed.find(update['feed']['id'])
    if update['entries'].any?
      update['entries'].each do |entry|
        begin
          if entry['update'] == true
            update_entry(entry)
          else
            create_entry(entry, feed)
          end
        rescue Exception
          FeedbinUtils.update_public_id_cache(entry['public_id'], entry['content'])
        end
      end
    end
    update_feed(update, feed)
  end

  def update_entry(entry)
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
  end

  def create_entry(entry, feed)
    feed.entries.create!(entry)
    Librato.increment('entry.create')
  end

  def update_feed
    feed.etag = update['feed']['etag']
    feed.last_modified = update['feed']['last_modified']
    feed.save
  end

end
