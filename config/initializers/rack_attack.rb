url = ENV["REDIS_URL_ENTRY_CREATED"] || ENV["REDIS_URL"] || nil
Rack::Attack.cache.store = Rack::Attack::StoreProxy::RedisStoreProxy.new(
  Redis.new(url: url, db: 1)
)

Rack::Attack.throttle("signups by ip", limit: 3, period: 1.day) do |request|
  path = request.path.split(".").first
  if ["/users", "/v2/users"].include?(path) && request.post?
    request.ip
  end
end