class IosPushNotificationSend
  include Sidekiq::Worker
  sidekiq_options retry: false, queue: :critical

  def perform(user_id, entry_ids)
    user = User.find(user_id)
    entries = Entry.find(entry_ids)
  end

end
