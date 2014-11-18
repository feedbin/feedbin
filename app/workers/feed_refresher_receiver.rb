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
    entry_update = entry.slice('author', 'content', 'title', 'url', 'entry_id', 'data')

    original_content_length = original_entry.content.to_s.length
    new_content_length = entry_update['content'].to_s.length

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

    if (new_content_length - original_content_length).abs > 30
      create_update_notifications(original_entry)
    end

    Librato.increment('entry.update')
  end

  def create_update_notifications(entry)
    updated_entries = []

    subscription_user_ids = Subscription.where(feed_id: entry.feed_id, active: true).pluck(:user_id)
    unread_entries_user_ids = UnreadEntry.where(entry_id: entry.id, user_id: subscription_user_ids).pluck(:user_id)
    updated_entries_user_ids = UpdatedEntry.where(entry_id: entry.id, user_id: subscription_user_ids).pluck(:user_id)

    subscription_user_ids.each do |user_id|
      if !unread_entries_user_ids.include?(user_id) && !updated_entries_user_ids.include?(user_id)
        updated_entries << UpdatedEntry.new_from_owners(user_id, entry)
      end
    end
    UpdatedEntry.import(updated_entries, validate: false)

    Librato.increment('entry.update_big')
  rescue Exception => e
    Honeybadger.notify(
      error_class: "FeedRefresherReceiver#create_update_notifications",
      error_message: "create_update_notifications failed",
      parameters: e
    )
  end

  def create_entry(entry, feed)
    feed.entries.create!(entry)
    Librato.increment('entry.create')
  end

  def update_feed(update, feed)
    feed.etag = update['feed']['etag']
    feed.last_modified = update['feed']['last_modified']
    feed.save
  end

end
