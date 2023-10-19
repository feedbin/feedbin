require "etc"
require "dotenv"
require "honeybadger"

working_directory = File.expand_path("..", __dir__)
max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
rails_environment = ENV.fetch("RAILS_ENV")         { "development" }
web_concurrency   = ENV.fetch("WEB_CONCURRENCY")   { Etc.nprocessors }

workers     web_concurrency
threads     min_threads_count, max_threads_count
environment rails_environment
plugin      :tmp_restart

if rails_environment == "production"
  pidfile File.join(working_directory, "tmp", "pids", "puma.pid")
  bind    File.join("unix://", working_directory, "tmp", "sockets", "puma.sock")
else
  port ENV.fetch("PORT") { 3000 }
end

on_booted do
  ENV.update Dotenv.load
end

lowlevel_error_handler do |exception|
  Honeybadger.notify(exception)
  [500, {}, ["An unknown error has occurred. Please contact #{ENV["FROM_ADDRESS"]} for support."]]
end
