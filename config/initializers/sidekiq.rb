require 'sidekiq'
require 'sidekiq/web'

Sidekiq::Web.app_url = ENV['FEEDBIN_URL']

Sidekiq.configure_server do |config|
  ActiveRecord::Base.establish_connection
  config.server_middleware do |chain|
    chain.add WorkerStat
  end
end
