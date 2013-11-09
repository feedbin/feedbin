class ActionsPerform
  include Sidekiq::Worker

  def perform(entry_id, matched_saved_search_ids)
    # Looks like [[8, 1, ["mark_read", "star"]], [7, 1, ["mark_read"]]]
    actions = Rails.cache.fetch("actions:all:array", expires_in: 5.minutes) { Action.all.pluck(:id, :user_id, :actions) }
    actions = actions.keep_if { |action_id, user_id, actions| matched_saved_search_ids.include?(action_id) }

    if actions.present?
      queues = {}
      actions.each do |action_id, user_id, action_names|
        action_names.each do |action_name|
          queues[action_name] ||= Set.new
          queues[action_name] << user_id
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