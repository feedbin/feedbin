# frozen_string_literal: true

Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add WorkerStat
  end
  config.redis = {id: "crawler-server-#{::Process.pid}"}
end

Sidekiq.configure_client do |config|
  config.redis = {id: "crawler-client-#{::Process.pid}"}
end

Sidekiq.strict_args!(false)
