class FeedRefresherReceiver
  include Sidekiq::Worker
  sidekiq_options queue: :feed_refresher_receiver

  def perform(params)
    feed = Feed.find(params["feed"]["id"])
    if params["entries"].present?
      params["entries"].each do |entry|
        update = entry.delete("update")
        begin
          if update == true
            update_entry(entry)
          else
            create_entry(entry, feed)
          end
        rescue ActiveRecord::RecordNotUnique
          FeedbinUtils.update_public_id_cache(entry["public_id"], entry["content"], entry["data"]["public_id_alt"])
          Librato.increment "entry.record_not_unique"
        rescue => error
          message = update ? "update" : "create"
          Honeybadger.notify(
            error_class: "FeedRefresherReceiver#" + message,
            error_message: "Entry #{message} failed",
            parameters: {feed_id: feed.id, entry: entry, exception: error, backtrace: error.backtrace},
          )
        end
      end
    end
    update_feed(params, feed)
  end

  def update_entry(entry)
    original_entry = Entry.find_by_public_id(entry["public_id"])
    if original_entry.present? && !original_entry.tweet?
      FeedbinUtils.update_public_id_cache(entry["public_id"], entry["content"], entry["data"]["public_id_alt"])
      if published_recently?(original_entry.published)
        entry_update = entry.slice("author", "content", "title", "url", "entry_id", "data")
        entry_update["summary"] = ContentFormatter.summary(entry_update["content"], 256)

        original_content = original_entry.content.to_s.clone
        new_content = entry_update["content"].to_s.clone

        if original_entry.original.nil?
          entry_update["original"] = build_original(original_entry)
        end
        original_entry.update_attributes(entry_update)

        if significant_change?(original_content, new_content)
          create_update_notifications(original_entry)
        end

        if new_content.length == original_content.length
          Librato.increment("entry.no_change")
        end

        Librato.increment("entry.update")
      end
    end
  end

  def build_original(original_entry)
    {
      "author" => original_entry.author,
      "content" => original_entry.content,
      "title" => original_entry.title,
      "url" => original_entry.url,
      "entry_id" => original_entry.entry_id,
      "published" => original_entry.published,
      "data" => original_entry.data,
    }
  end

  def published_recently?(published_date)
    published_date > 7.days.ago
  end

  def significant_change?(original_content, new_content)
    original_length = Sanitize.fragment(original_content).length
    new_length = Sanitize.fragment(new_content).length
    new_length - original_length > 50
  rescue Exception => e
    Honeybadger.notify(
      error_class: "FeedRefresherReceiver#detect_significant_change",
      error_message: "detect_significant_change failed",
      parameters: {exception: e, backtrace: e.backtrace},
    )
    false
  end

  def create_update_notifications(entry)
    updated_entries = []

    subscription_user_ids = Subscription.where(feed_id: entry.feed_id, active: true, muted: false, show_updates: true).pluck(:user_id)
    unread_entries_user_ids = UnreadEntry.where(entry_id: entry.id, user_id: subscription_user_ids).pluck(:user_id)
    updated_entries_user_ids = UpdatedEntry.where(entry_id: entry.id, user_id: subscription_user_ids).pluck(:user_id)

    subscription_user_ids.each do |user_id|
      if !unread_entries_user_ids.include?(user_id) && !updated_entries_user_ids.include?(user_id)
        updated_entries << UpdatedEntry.new_from_owners(user_id, entry)
      end
    end
    UpdatedEntry.import(updated_entries, validate: false)

    Librato.increment("entry.update_big")
  rescue Exception => e
    Honeybadger.notify(
      error_class: "FeedRefresherReceiver#create_update_notifications",
      error_message: "create_update_notifications failed",
      parameters: {exception: e, backtrace: e.backtrace},
    )
  end

  def create_entry(entry, feed)
    if alternate_exists?(entry)
      Librato.increment("entry.alternate_exists")
    else
      threader = Threader.new(entry, feed)
      if !threader.thread
        feed.entries.create!(entry)
        Librato.increment("entry.create")
      else
        Librato.increment("entry.thread")
      end
    end
  end

  def alternate_exists?(entry)
    if entry["data"] && entry["data"]["public_id_alt"]
      Entry.where(public_id: entry["data"]["public_id_alt"]).exists? || FeedbinUtils.public_id_exists?(entry["data"]["public_id_alt"])
    end
  end

  def update_feed(update, feed)
    feed.update(update["feed"])
  end
end
