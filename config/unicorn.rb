worker_processes 16

app_name = "feedbin"
app_dir  = "/srv/apps/#{app_name}"
working_directory "#{app_dir}/current"

user 'app', 'app'

rails_env = ENV['RAILS_ENV'] || 'production'

# Log everything to one file
stderr_path "#{app_dir}/shared/log/unicorn.log"
stdout_path "#{app_dir}/shared/log/unicorn.log"

listen "#{app_dir}/shared/system/unicorn.sock"

timeout 30

pid "#{app_dir}/shared/pids/unicorn.pid"

preload_app true
GC.respond_to?(:copy_on_write_friendly=) and GC.copy_on_write_friendly = true

before_fork do |server, worker|
  defined?(ActiveRecord::Base) and ActiveRecord::Base.connection.disconnect!
end

after_fork do |server, worker|
  Sidekiq.configure_client do |config|
    config.redis = { size: 1 }
  end

  defined?(ActiveRecord::Base) and ActiveRecord::Base.establish_connection

  # Kill off the new master after forking
  old_pid = "#{app_dir}/shared/pids/unicorn.pid.oldbin"
  if File.exists?(old_pid) && server.pid != old_pid
    begin
      Process.kill("QUIT", File.read(old_pid).to_i)
    rescue Errno::ENOENT, Errno::ESRCH
      # someone else did our job for us
    end
  end
end
