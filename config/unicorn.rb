require "dotenv"

worker_processes Etc.nprocessors
timeout 30
preload_app true
user "app", "app"

listen "/tmp/unicorn.sock"

app_dir = "/srv/apps/feedbin"
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
  if ENV["ENV_PATH"]
    begin
      ENV.update Dotenv::Environment.new(ENV["ENV_PATH"], true)
    rescue ArgumentError
      ENV.update Dotenv::Environment.new(ENV["ENV_PATH"])
    end
  end
end
