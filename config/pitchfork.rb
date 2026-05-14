require "etc"

worker_processes ENV.fetch("WEB_CONCURRENCY", Etc.nprocessors).to_i
timeout 30

if ENV.fetch("RAILS_ENV", "development") == "production"
  require "dotenv"

  after_mold_fork do |_server, _mold|
    defined?(ActiveRecord::Base) && ActiveRecord::Base.connection.disconnect!
    Process.warmup
  end

  after_worker_fork do |_server, _worker|
    defined?(ActiveRecord::Base) && ActiveRecord::Base.establish_connection
  end
end
