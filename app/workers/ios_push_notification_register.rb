class IosPushNotificationRegister
  include Sidekiq::Worker
  sidekiq_options retry: false, queue: :critical

  def perform(entry_id, user_ids)
    push_queue_key = "pushes_to_send"
    user_ids.each do |user_id|
      key = "push_to_send:#{user_id}"
      $redis.sadd(key, entry_id)
      $redis.sadd(push_queue_key, key)
    end
  end

end
