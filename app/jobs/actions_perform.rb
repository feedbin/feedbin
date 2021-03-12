require "sidekiq/api"

class ActionsPerform
  include Sidekiq::Worker
  sidekiq_options queue: :critical, retry: false

  def perform(entry_id, action_ids, update = false)
    # Looks like [[8, 1, ["mark_read", "star"]], [7, 1, ["mark_read"]]]
    actions = Action.where(id: action_ids).pluck(:id, :user_id, :actions)
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
        if !update && action_name == "send_push_notification"
          SafariPushNotificationSend.perform_async(user_ids, entry_id) unless update
        elsif !update && action_name == "star"
          star(user_ids, user_actions) unless update
        elsif action_name == "mark_read"
          if update
            UpdatedEntry.where(user_id: user_ids, entry_id: entry_id).delete_all
          else
            UnreadEntry.where(user_id: user_ids, entry_id: entry_id).delete_all
          end
        elsif !update && action_name == "send_ios_notification"
          send_ios_notification(user_ids) unless update
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
      job = EntryImage.new
      job.entry = @entry
      if job_args = job.build_job
        Sidekiq::Client.push(
          "args" => job_args,
          "class" => "FindImageCritical",
          "queue" => "image_parallel_critical",
          "retry" => false
        )
      end
    end
    DevicePushNotificationSend.perform_in(1.minute, user_ids, @entry.id, true)
  end
end
