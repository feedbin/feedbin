if ENV['REDIS_URL_FEED_ENTRIES_CREATED_AT']
  url = ENV['REDIS_URL_FEED_ENTRIES_CREATED_AT']
else
  url = ENV['REDIS_URL']
end
$redis = Redis.new(url: url)