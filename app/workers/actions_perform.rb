class ActionsPerform
  include Sidekiq::Worker

  def perform(entry_id, feed_id)
    actions = Rails.cache.fetch("actions:all", expires_in: 5.minutes) { Action.all.all }
    actions = actions.keep_if { |action| action.feed_ids.include?(feed_id.to_s) }

    if actions.present?
      queries = actions.map {|action| action.query }
      entries = Entry.action_search(entry_id, queries)

      queues = {}
      entries.each_with_index do |entry, index|
        unless entry.results.empty?
          action = actions[index]
          action.actions.each do |action_name|
            queues[action_name] ||= Set.new
            queues[action_name] << action.user_id
          end
        end
      end

      queues.each do |action_name, user_ids|
        user_ids = user_ids.to_a
        if action_name == 'send_push_notification'
          PushNotificationSend.perform_async(entry_id, user_ids)
        elsif action_name == 'star'
          users = User.where(id: user_ids)
          entry = Entry.find(entry_id)
          users.each {|user| StarredEntry.create_from_owners(user, entry) }
        elsif action_name == 'mark_read'
          UnreadEntry.where(user_id: user_ids, entry_id: entry_id).delete_all
        end
      end

      Librato.increment 'actions_performed', by: 1

    end
  end
end