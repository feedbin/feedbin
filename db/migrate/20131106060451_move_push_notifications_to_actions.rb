class MovePushNotificationsToActions < ActiveRecord::Migration[4.2]
  def up
    User.find_each do |user|
      feed_ids = user.subscriptions.where(push: true).pluck(:feed_id)
      if feed_ids.any?
        user.actions.create(feed_ids: feed_ids, actions: ["send_push_notification"])
      end
    rescue Exception
    end
  end

  def down
  end
end
