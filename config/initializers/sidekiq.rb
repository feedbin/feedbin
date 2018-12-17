require "sidekiq"

Sidekiq::Extensions.enable_delay!
Sidekiq.configure_server do |config|
  ActiveRecord::Base.establish_connection
  config.server_middleware do |chain|
    chain.add WorkerStat
  end
end
