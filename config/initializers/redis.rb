redis_options = {connect_timeout: 5, timeout: 5}
if ENV['REDIS_URL_ENTRY_CREATED']
  redis_options[:url] = ENV['REDIS_URL_ENTRY_CREATED']
elsif ENV['REDIS_URL']
  redis_options[:url] = ENV['REDIS_URL']
end
$redis = Redis.new(redis_options)


redis_id_options = {connect_timeout: 5, timeout: 5}
if ENV['REDIS_ID_URL']
  redis_id_options[:url] = ENV['REDIS_ID_URL']
elsif ENV['REDIS_URL']
  redis_id_options[:url] = ENV['REDIS_URL']
end
$redis_id_cache = Redis.new(redis_id_options)
