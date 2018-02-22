module RecordStatus

  def record_status(feed_id, status)
    $redis.with do |connection|
      connection.pipelined do
        connection.lpush(list_name(feed_id), status)
        connection.ltrim(list_name(feed_id), 0, 99)
        connection.lrange(list_name(feed_id), 0, 99)
      end
    end
  end

  def list_name(feed_id)
    "feed:#{feed_id}:status"
  end

end