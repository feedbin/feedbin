require "etc"
require "dotenv"
require "honeybadger"

max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }

workers ENV.fetch("WEB_CONCURRENCY") { "2" }
threads min_threads_count, max_threads_count
environment ENV.fetch("RAILS_ENV", "development")

pp File.expand_path("..", __dir__)
pp ENV

if @options[:environment] == "production"
  shared_directory = File.join(File.expand_path("..", ENV["PWD"]), "shared")
  shared_directory = File.directory?(shared_directory) ? shared_directory : ENV["PWD"]
  pidfile File.join(shared_directory, "tmp", "puma.pid")
  bind    File.join("unix://", shared_directory, "tmp", "puma.sock")
else
  port ENV.fetch("PORT") { 3000 }
end

plugin :tmp_restart

on_booted do
  ENV.update Dotenv.load
end

lowlevel_error_handler do |exception|
  Honeybadger.notify(exception)
  [500, {}, ["An unknown error has occurred. Please contact #{ENV["FROM_ADDRESS"]} for support."]]
end
