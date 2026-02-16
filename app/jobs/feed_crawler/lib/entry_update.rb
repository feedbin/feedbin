module FeedCrawler
  class EntryUpdate
    def initialize(updated_data, original_entry)
      @updated_data = updated_data
      @original_entry = original_entry
    end

    def self.create!(updated_data, original_entry)
      new(updated_data, original_entry).create
    end

    def create

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
        Honeybadger.increment_counter("entry.change", source: "large")
      else
        Honeybadger.increment_counter("entry.change", source: "small")
      end

      changes = update.each_with_object([]) do |(attribute, value), array|
        if value != @original_entry.public_send(attribute)
          array.push(attribute)
        end
      end

      Sidekiq.logger.info "Updating entry=#{@original_entry.public_id} changes=#{changes.join(",")}"

      @original_entry.update(update)

      Honeybadger.increment_counter("entry.update")
    end

    def significant_change?(current_content, new_content)
      return false if current_content.empty?
      return false if current_content == new_content

      original_length = Sanitize.fragment(current_content).length
      new_length = Sanitize.fragment(new_content).length
      new_length - original_length > 50
    rescue Exception => e
      ErrorService.notify(
        error_class: "Receiver#detect_significant_change",
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

      Honeybadger.increment_counter("entry.update_big")
    rescue Exception => e
      ErrorService.notify(
        error_class: "Receiver#create_update_notifications",
        error_message: "create_update_notifications failed",
        parameters: {exception: e, backtrace: e.backtrace}
      )
    end
  end
end