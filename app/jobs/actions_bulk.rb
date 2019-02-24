class ActionsBulk
  include Sidekiq::Worker
  sidekiq_options queue: :default, retry: false

  def perform(action_id, user_id)
    user = User.find(user_id)
    action = user.actions.find(action_id)

    entry_ids = []
    action.scrolled_results do |result|
      ids = result["hits"]["hits"].map { |hit|
        hit["_id"].to_i
      }
      entry_ids.concat(ids)
    end

    action.actions.each do |task|
      case task
      when "send_push_notificationx"
        entry_ids.map do |entry_id|
          SafariPushNotificationSend.perform_async([user.id], entry_id)
        end
      when "star"
        Entry.where(id: entry_ids).find_in_batches do |entries|
          entries.each do |entry|
            StarredEntry.create_from_owners(user, entry, "ActionsExisting: #{action.id}")
          end
        end
      when "mark_read"
        user.unread_entries.where(entry_id: entry_ids).delete_all
      end
    end
  end
end
