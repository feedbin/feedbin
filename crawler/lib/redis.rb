$redis = ConnectionPool.new(size: 3, timeout: 5) do
  if ENV['REDIS_ID_URL']
    Redis.new(url: ENV['REDIS_ID_URL'])
  else
    Redis.new
  end
end