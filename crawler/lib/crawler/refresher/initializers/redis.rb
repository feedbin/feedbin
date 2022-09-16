# frozen_string_literal: true

$redis = ConnectionPool.new(size: 3, timeout: 5) {
  if ENV["REDIS_ID_URL"]
    Redis.new(url: ENV["REDIS_ID_URL"])
  else
    Redis.new
  end
}
