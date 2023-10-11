defaults = {connect_timeout: 5, timeout: 5}
defaults[:url] = ENV["REDIS_URL"] if ENV["REDIS_URL"]

unless Rails.env.test?
  $redis = {}.tap do |hash|
    options2 = defaults.dup
    if ENV["REDIS_URL_PUBLIC_IDS"] || ENV["REDIS_URL_CACHE"]
      options2[:url] = ENV["REDIS_URL_PUBLIC_IDS"] || ENV["REDIS_URL_CACHE"]
    end
    hash[:refresher] = ConnectionPool.new(size: 10) { Redis.new(options2) }
  end
end
