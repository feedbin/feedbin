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
  old_pid = "#{app_dir}/shared/tmp/pids/unicorn.pid.oldbin"
  if File.exists?(old_pid) && server.pid != old_pid
    begin
      Process.kill("QUIT", File.read(old_pid).to_i)
    rescue Errno::ENOENT, Errno::ESRCH
      # someone else did our job for us
    end
  end
end

after_fork do |server, worker|
  defined?(ActiveRecord::Base) && ActiveRecord::Base.establish_connection
end

before_exec do |server|
  # Dotenv.load
end
