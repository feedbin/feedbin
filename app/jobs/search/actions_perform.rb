require "sidekiq/api"

module Search
  class ActionsPerform
    include Sidekiq::Worker
    sidekiq_options queue: :network_search, retry: false

    def perform(entry_id, action_ids, update = false)
      Sidekiq.logger.info("#{entry_id} actions_ids=#{action_ids}")
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

        # send_ios_notification is the retired Notifier's value. Both push to
        # every device the user has registered, once per user however many
        # actions matched.
        pushes = Set.new.merge(queues.delete("send_push_notification") || []).merge(queues.delete("send_ios_notification") || [])
        if !update && pushes.any?
          priority_image_crawl
          DevicePushNotificationSend.perform_in(1.minute, pushes.to_a, entry_id, true)
          WebPushNotificationSend.perform_in(1.minute, pushes.to_a, entry_id, true)
        end

        queues.each do |action_name, user_ids|
          user_ids = user_ids.to_a
          if !update && action_name == "star"
            star(user_ids, user_actions)
          elsif action_name == "mark_read"
            UnreadEntry.where(user_id: user_ids, entry_id: entry_id).delete_all
            if update
              UpdatedEntry.where(user_id: user_ids, entry_id: entry_id).delete_all
            end
          end
        end
        Librato.increment "actions_performed", by: 1
      end
    end

    private

    def star(user_ids, user_actions)
      # A suspended account can still match here until its percolators are
      # removed. Never write stars for it. Mirrors Entry#mark_as_unread,
      # which filters unreads on Subscription.active.
      users = User.where(id: user_ids, suspended: false)
      users.each do |user|
        message = "action"
        if user_actions[user.id].present?
          actions = user_actions[user.id].join(",")
          message = "#{message} #{actions}"
        end
        # The cap has to guard the write, not sit next to it. An action with a
        # broad query matches most of a user's intake, and every match is a
        # star they never asked for and have to delete by hand.
        starred = Throttle.throttle!("starred_entries:create:#{user.id}", 100, 1.day) do
          StarredEntry.create_from_owners(user, @entry, message)
        end
        if starred == false
          Sidekiq.logger.info "Auto-star limit reached user_id=#{user.id} entry_id=#{@entry.id}"
        end
      end
    end

    def priority_image_crawl
      job = ImageCrawler::EntryImage.new
      job.entry = @entry
      if job_args = job.build_job
        ImageCrawler::Pipeline::FindCritical.perform_async(job_args)
      end
    end
  end
end