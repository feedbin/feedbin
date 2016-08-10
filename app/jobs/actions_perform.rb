class ActionsPerform
  include Sidekiq::Worker
  sidekiq_options queue: :critical

  def perform(entry_id, matched_saved_search_ids)
    # Looks like [[8, 1, ["mark_read", "star"]], [7, 1, ["mark_read"]]]
    actions = Rails.cache.fetch("actions:all:array", expires_in: 5.minutes) { Action.all.pluck(:id, :user_id, :actions) }
    actions = actions.keep_if { |action_id, user_id, actions| matched_saved_search_ids.include?(action_id) }

    if actions.present?
      queues = {}
      user_actions = {}
      actions.each do |action_id, user_id, action_names|
        user_actions[user_id] ||= []
        user_actions[user_id] << action_id
        action_names.each do |action_name|
          queues[action_name] ||= Set.new
          queues[action_name] << user_id
        end
      end

      queues.each do |action_name, user_ids|
        user_ids = user_ids.to_a
        if action_name == 'send_push_notification'
          SafariPushNotificationSend.perform_async(user_ids, entry_id)
        elsif action_name == 'star'
          users = User.where(id: user_ids)
          entry = Entry.find(entry_id)
          users.each do |user|
            message = "action"
            if user_actions[user.id].present?
              message = "#{message} #{user_actions[user.id].join(',')}"
            end
            Throttle.throttle!("starred_entries:create:#{user.id}", 100, 1.day) do
              StarredEntry.create_from_owners(user, entry, message)
            end
          end
        elsif action_name == 'mark_read'
          UnreadEntry.where(user_id: user_ids, entry_id: entry_id).delete_all
        elsif action_name == 'send_ios_notification'
          DevicePushNotificationSend.perform_async(user_ids, entry_id)
        end
      end

      Librato.increment 'actions_performed', by: 1

    end
  end
end