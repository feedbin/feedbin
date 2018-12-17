defaults = {connect_timeout: 5, timeout: 5}
defaults.merge!(url: ENV["REDIS_URL"]) if ENV["REDIS_URL"]

$redis = Hash.new.tap do |hash|
  options1 = defaults.dup
  if ENV["REDIS_URL_ENTRY_CREATED"]
    options1.merge!(url: ENV["REDIS_URL_ENTRY_CREATED"])
  end
  hash[:sorted_entries] = ConnectionPool.new(size: 10) { Redis.new(options1) }

  options2 = defaults.dup
  if ENV["REDIS_ID_URL"]
    options2.merge!(url: ENV["REDIS_ID_URL"])
  end
  hash[:id_cache] = ConnectionPool.new(size: 10) { Redis.new(options2) }
end
