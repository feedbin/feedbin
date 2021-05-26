require "sidekiq"

SIDEKIQ_ALT = ConnectionPool.new(size: 1, timeout: 2) { Redis.new(timeout: 1.0) }

Sidekiq::Extensions.enable_delay!
Sidekiq.configure_server do |config|
  ActiveRecord::Base.establish_connection
  config.server_middleware do |chain|
    chain.add WorkerStat
  end
  config.redis = {id: "feedbin-server-#{::Process.pid}"}
end

Sidekiq.configure_client do |config|
  config.redis = {id: "feedbin-client-#{::Process.pid}"}
end
