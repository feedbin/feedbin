require "sidekiq/api"

class ActionsPerform
  include Sidekiq::Worker
  sidekiq_options queue: :critical, retry: false

  def perform(entry_id, matched_saved_search_ids)
    # Looks like [[8, 1, ["mark_read", "star"]], [7, 1, ["mark_read"]]]
    actions = Rails.cache.fetch("actions:all:array", expires_in: 5.minutes) { Action.all.pluck(:id, :user_id, :actions) }
    actions = actions.keep_if { |action_id, user_id, actions| matched_saved_search_ids.include?(action_id) }
    @entry = Entry.find(entry_id)

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
        if action_name == "send_push_notification"
          SafariPushNotificationSend.perform_async(user_ids, entry_id)
        elsif action_name == "star"
          star(user_ids, user_actions)
        elsif action_name == "mark_read"
          UnreadEntry.where(user_id: user_ids, entry_id: entry_id).delete_all
        elsif action_name == "send_ios_notification"
          send_ios_notification(user_ids)
        end
      end
      Librato.increment "actions_performed", by: 1
    end
  end

  private

  def star(user_ids, user_actions)
    users = User.where(id: user_ids)
    users.each do |user|
      message = "action"
      if user_actions[user.id].present?
        actions = user_actions[user.id].join(",")
        message = "#{message} #{actions}"
      end
      Throttle.throttle!("starred_entries:create:#{user.id}", 100, 1.day) do
      end
      StarredEntry.create_from_owners(user, @entry, message)
    end
  end

  def send_ios_notification(user_ids)
    if Sidekiq::Queue.new("images").size > 10
      Sidekiq::Client.push(
        "args" => EntryImage.build_find_image_args(@entry),
        "class" => "FindImageCritical",
        "queue" => "images_critical",
        "retry" => false,
      )
    end
    DevicePushNotificationSend.perform_in(1.minute, user_ids, @entry.id, true)
  end
end
