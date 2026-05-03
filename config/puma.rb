require "etc"

rails_env = ENV.fetch("RAILS_ENV", "development")
environment rails_env

if rails_env == "production"
  require "dotenv"

  prune_bundler true
  workers :auto

  before_fork do
    defined?(ActiveRecord::Base) && ActiveRecord::Base.connection.disconnect!

    # Autotuner recommendation
    3.times { GC.start }
    GC.compact
  end

  before_worker_boot do
    defined?(ActiveRecord::Base) && ActiveRecord::Base.establish_connection
  end

  before_restart do
    ENV.update Dotenv.load
  end
else
  port    ENV.fetch("PORT", 3000)
  threads ENV.fetch("RAILS_MIN_THREADS", 5).to_i, ENV.fetch("RAILS_MAX_THREADS", 5).to_i
  workers ENV.fetch("WEB_CONCURRENCY", 0).to_i

  plugin :tmp_restart
end
