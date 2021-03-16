$redis = begin
  if ENV["REDIS_ID_URL"]
    Redis.new(url: ENV["REDIS_ID_URL"])
  else
    Redis.new
  end
end
