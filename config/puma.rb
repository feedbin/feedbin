deploy_dir = File.expand_path("../../../..", __FILE__)
shared_dir = "#{deploy_dir}/shared"

stdout_redirect "#{shared_dir}/log/puma.stdout.log", "#{shared_dir}/log/puma.stderr.log", true

pidfile "#{shared_dir}/pids/puma.pid"
state_path "#{shared_dir}/pids/puma.state"
activate_control_app

threads_count = ENV.fetch("RAILS_MAX_THREADS") { 4 }.to_i
threads threads_count, threads_count

bind 'unix:///var/run/puma.sock'

environment ENV.fetch("RAILS_ENV") { "development" }

workers ENV.fetch("WEB_CONCURRENCY") { 4 }

preload_app!

on_worker_boot do
  ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
end

before_fork do
  if ENV['ENV_PATH']
    ENV.update Dotenv::Environment.new(ENV['ENV_PATH'])
  end
end

# Allow puma to be restarted by `rails restart` command.
plugin :tmp_restart
