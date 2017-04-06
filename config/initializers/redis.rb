defaults = {connect_timeout: 5, timeout: 5}
defaults.merge!(url: ENV['REDIS_URL']) if ENV['REDIS_URL']

$redis = Hash.new.tap do |hash|
  options = defaults.dup
  if ENV['REDIS_URL_ENTRY_CREATED']
    options.merge!(url: ENV['REDIS_URL_ENTRY_CREATED'])
  end
  hash[:sorted_entries] = Redis.new(options)

  options = defaults.dup
  if ENV['REDIS_ID_URL']
    options.merge!(url: ENV['REDIS_ID_URL'])
  end
  hash[:id_cache] = Redis.new(options)
end
