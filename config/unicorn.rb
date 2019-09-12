require "dotenv"

worker_processes Etc.nprocessors
timeout 30
preload_app true
user "app", "app"

app_dir = "/srv/apps/feedbin"
shared_dir = "#{app_dir}/shared"

working_directory "#{app_dir}/current"

listen      "#{shared_dir}/tmp/sockets/unicorn.sock"
pid         "#{shared_dir}/tmp/pids/unicorn.pid"
stderr_path "#{shared_dir}/log/unicorn.log"
stdout_path "#{shared_dir}/log/unicorn.log"

before_fork do |server, worker|
  defined?(ActiveRecord::Base) && ActiveRecord::Base.connection.disconnect!
end

after_fork do |server, worker|
  defined?(ActiveRecord::Base) && ActiveRecord::Base.establish_connection
end

before_exec do |server|
  # Dotenv.load
end
