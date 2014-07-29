if ENV['REDIS_URL_ENTRY_CREATED']
  url = ENV['REDIS_URL_ENTRY_CREATED']
else
  url = ENV['REDIS_URL']
end
$redis = Redis.new(url: url)