require "etc"

rails_env = ENV.fetch("RAILS_ENV", "development")
environment rails_env

if rails_env == "production"
  require "dotenv"

  # systemd sets the working directory to the Capistrano `current` symlink, so the
  # deploy root is one level up and `shared/` is its sibling.
  shared_path = File.expand_path("../shared", Dir.pwd)
  shared_path = Dir.pwd unless File.directory?(shared_path)

  # Match the Capistrano-Puma plugin's defaults so the systemd unit, nginx upstream,
  # and pumactl all agree on where to find the socket/pid/state files.
  bind       "unix://#{File.join(shared_path, "tmp", "puma.sock")}"
  pidfile    File.join(shared_path, "tmp", "puma.pid")
  state_path File.join(shared_path, "tmp", "puma.state")

  workers Integer(ENV.fetch("WEB_CONCURRENCY", Etc.nprocessors))
  threads 1, 1
  preload_app!

  before_fork do
    defined?(ActiveRecord::Base) && ActiveRecord::Base.connection.disconnect!

    # Autotuner recommendation: compact the heap before forking so workers share more CoW pages.
    3.times { GC.start }
    GC.compact
  end

  before_worker_boot do
    defined?(ActiveRecord::Base) && ActiveRecord::Base.establish_connection
  end

  # Hot restart re-execs puma; refresh env from .env so the new master sees current values.
  before_restart do
    ENV.update Dotenv.load
  end
else
  port    ENV.fetch("PORT", 3000)
  threads ENV.fetch("RAILS_MIN_THREADS", 5).to_i, ENV.fetch("RAILS_MAX_THREADS", 5).to_i
  workers ENV.fetch("WEB_CONCURRENCY", 0).to_i

  plugin :tmp_restart
end
