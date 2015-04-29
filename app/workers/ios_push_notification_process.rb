class IosPushNotificationProcess
  include Sidekiq::Worker
  sidekiq_options retry: false, queue: :critical

  def perform()
    push_queue_key = "pushes_to_send"
    keys, _ = $redis.multi do
      $redis.smembers(push_queue_key)
      $redis.del(push_queue_key)
    end

    keys.each do |key|
      user_id = key.split(':').last
      entry_ids, _ = $redis.multi do
        $redis.smembers(key)
        $redis.del(key)
      end
      IosPushNotificationSend.perform_async(user_id, entry_ids)
    end
  end

end
