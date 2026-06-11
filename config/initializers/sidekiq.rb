require "sidekiq"
require ::File.expand_path("../../../lib/job_stat", __FILE__)

Sidekiq.strict_args!(false)

# Sidekiq::Extensions.enable_delay!

Sidekiq.configure_server do |config|
  config.logger.formatter = Sidekiq::Logger::Formatters::Plain.new
  ActiveRecord::Base.establish_connection
  config.server_middleware do |chain|
    chain.add JobStat
  end
  config.redis = {id: "feedbin-server-#{::Process.pid}"}
end

Sidekiq.configure_client do |config|
  config.redis = {id: "feedbin-client-#{::Process.pid}"}
end
