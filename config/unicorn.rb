require "dotenv"

worker_processes Etc.nprocessors
timeout 30
preload_app true
user "app", "app"

app_dir = "/srv/apps/feedbin"

listen "#{app_dir}/shared/tmp/sockets/unicorn.sock"
working_directory "#{app_dir}/current"
stderr_path "#{app_dir}/shared/log/unicorn.log"
stdout_path "#{app_dir}/shared/log/unicorn.log"
pid "#{app_dir}/shared/tmp/pids/unicorn.pid"

before_fork do |server, worker|
  defined?(ActiveRecord::Base) && ActiveRecord::Base.connection.disconnect!
end

after_fork do |server, worker|
  defined?(ActiveRecord::Base) && ActiveRecord::Base.establish_connection
  old_pid = "#{app_dir}/shared/tmp/pids/unicorn.pid.oldbin"
  if old_pid != server.pid
    begin
      sig = (worker.nr + 1) >= server.worker_processes ? :QUIT : :TTOU
      Process.kill(sig, File.read(old_pid).to_i)
    rescue Errno::ENOENT, Errno::ESRCH
    end
  end
end

before_exec do |server|
  Dotenv.load
end
