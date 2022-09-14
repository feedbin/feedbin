class FeedRefresherReceiver
  include Sidekiq::Worker
  sidekiq_options queue: :feed_refresher_receiver

  def perform(data)
    feed = Feed.find(data["feed"]["id"])
    if data["entries"].present?
      receive_entries(data["entries"], feed)
    end
    feed.update(data["feed"])
  end

  def receive_entries(items, feed)
    public_ids = items.map { |entry| entry["public_id"] }
    entries = Entry.where(public_id: public_ids).index_by(&:public_id)
    items.each do |item|
      entry = entries[item["public_id"]]
      update = item.delete("update")
      if entry
        EntryUpdate.create!(item, entry)
      else
        create_entry(item, feed)
      end
    rescue ActiveRecord::RecordNotUnique
      # Ignore
    rescue => exception
      unless exception.message =~ /Validation failed/i
        message = update ? "update" : "create"
        ErrorService.notify(
          error_class: "FeedRefresherReceiver#" + message,
          error_message: "Entry #{message} failed",
          parameters: {feed_id: feed.id, item: item, exception: exception, backtrace: exception.backtrace}
        )
        Sidekiq.logger.info "Entry Error: feed=#{feed.id} exception=#{exception.inspect}"
      end
    end
  end

  def create_entry(item, feed)
    if alternate_exists?(item)
      Librato.increment("entry.alternate_exists")
    else
      threader = Threader.new(item, feed)
      if !threader.thread
        feed.entries.create!(item)
        Librato.increment("entry.create")
      else
        Librato.increment("entry.thread")
      end
      Sidekiq.logger.info "Creating entry=#{item["public_id"]}"
    end
  end

  def alternate_exists?(item)
    if item["data"] && item["data"]["public_id_alt"]
      FeedbinUtils.public_id_exists?(item["data"]["public_id_alt"])
    end
  end
end

class EntryUpdate
  def initialize(updated_data, original_entry)
    @updated_data = updated_data
    @original_entry = original_entry
  end

  def self.create!(updated_data, original_entry)
    new(updated_data, original_entry).create
  end

  def create
    Sidekiq.logger.info "Updating entry=#{@original_entry.public_id}"

    update          = @updated_data.slice("author", "content", "title", "url", "entry_id", "data", "fingerprint")
    current_content = @original_entry.content.to_s.clone
    new_content     = update["content"].to_s.clone

    if significant_change?(current_content, new_content) && @original_entry.published_recently?
      create_update_notifications(@original_entry)
      if @original_entry.original.nil?
        update["original"] = {
          "author"      => @original_entry.author,
          "content"     => @original_entry.content,
          "title"       => @original_entry.title,
          "url"         => @original_entry.url,
          "entry_id"    => @original_entry.entry_id,
          "published"   => @original_entry.published,
          "data"        => @original_entry.data,
          "fingerprint" => @original_entry.fingerprint,
        }
      end
    end

    @original_entry.update(update)
    Librato.increment("entry.update")
  end

  def significant_change?(current_content, new_content)
    return false if current_content.empty?
    return false if current_content == new_content

    original_length = Sanitize.fragment(current_content).length
    new_length = Sanitize.fragment(new_content).length
    new_length - original_length > 50
  rescue Exception => e
    ErrorService.notify(
      error_class: "FeedRefresherReceiver#detect_significant_change",
      error_message: "detect_significant_change failed",
      parameters: {exception: e, backtrace: e.backtrace}
    )
    false
  end

  def create_update_notifications(entry)
    updated_entries = []

    subscription_user_ids = Subscription.where(feed_id: @original_entry.feed_id, active: true, muted: false, show_updates: true).pluck(:user_id)
    unread_entries_user_ids = UnreadEntry.where(entry_id: @original_entry.id, user_id: subscription_user_ids).pluck(:user_id)
    updated_entries_user_ids = UpdatedEntry.where(entry_id: @original_entry.id, user_id: subscription_user_ids).pluck(:user_id)

    subscription_user_ids.each do |user_id|
      if !unread_entries_user_ids.include?(user_id) && !updated_entries_user_ids.include?(user_id)
        updated_entries << UpdatedEntry.new_from_owners(user_id, @original_entry)
      end
    end
    UpdatedEntry.import(updated_entries, validate: false, on_duplicate_key_ignore: true)

    Librato.increment("entry.update_big")
  rescue Exception => e
    ErrorService.notify(
      error_class: "FeedRefresherReceiver#create_update_notifications",
      error_message: "create_update_notifications failed",
      parameters: {exception: e, backtrace: e.backtrace}
    )
  end
end
