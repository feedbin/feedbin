class Threader
  def initialize(entry_hash, feed)
    @entry_hash = ActiveSupport::HashWithIndifferentAccess.new(entry_hash)
    @feed = feed
    @thread_id = @entry_hash["thread_id"]
    @reply_to = @entry_hash.dig("data", "tweet", "in_reply_to_status_id")
  end

  def thread
    if entry = parent_entry
      updated_thread = entry.thread.push(@entry_hash["data"]["tweet"])
      entry.data["thread"] = updated_thread
      entry.thread_id = @thread_id
      entry.save!
      FeedbinUtils.update_public_id_cache(@entry_hash["public_id"], @entry_hash["content"])
      create_updated_entries
    end
  rescue => e
    Honeybadger.notify(e)
    false
  end

  def parent_entry
    @parent_entry ||= begin
      entry = false
      if @thread_id && @reply_to
        if parent_entry = @feed.entries.where(thread_id: @reply_to)
          if parent_entry.length == 1 && same_user?(parent_entry)
            entry = parent_entry.first
          end
        end
      end
      entry
    end
  end

  def create_updated_entries
    subscription_user_ids = Subscription.where(feed_id: parent_entry.feed_id, active: true, muted: false, show_updates: true).pluck(:user_id)
    unread_entries_user_ids = UnreadEntry.where(entry_id: parent_entry.id, user_id: subscription_user_ids).pluck(:user_id)
    updated_entries_user_ids = UpdatedEntry.where(entry_id: parent_entry.id, user_id: subscription_user_ids).pluck(:user_id)

    updated_entries = subscription_user_ids.each_with_object([]) { |user_id, array|
      if !unread_entries_user_ids.include?(user_id) && !updated_entries_user_ids.include?(user_id)
        array << UpdatedEntry.new_from_owners(user_id, parent_entry)
      end
    }
    UpdatedEntry.import(updated_entries, validate: false)
  end

  def same_user?(parents)
    parent = parents.first
    parent.data.dig("tweet", "user", "screen_name") == @entry_hash.dig("data", "tweet", "user", "screen_name")
  end
end
