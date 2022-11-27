require "sidekiq"
require ::File.expand_path("../../../lib/job_stat", __FILE__)

SIDEKIQ_ALT = ConnectionPool.new(size: 1, timeout: 2) { Redis.new(timeout: 1.0) }

Sidekiq.strict_args!(false)
Sidekiq::Extensions.enable_delay!
Sidekiq.configure_server do |config|
  ActiveRecord::Base.establish_connection
  config.server_middleware do |chain|
    chain.add JobStat
  end
  config.redis = {id: "feedbin-server-#{::Process.pid}"}
end

Sidekiq.configure_client do |config|
  config.redis = {id: "feedbin-client-#{::Process.pid}"}
end

module Sidekiq
  class Batch
    def self.cleanup_redis(bid)
      # noop
    end
  end
end

module Sidekiq
  class Batch
    class Status
      def join
        sleep 0.01 until complete?
      end
    end
  end
end
