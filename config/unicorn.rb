require "dotenv"
require "etc"

working_directory File.expand_path("..", __dir__)
shared_directory = File.join(File.expand_path("..", ENV["PWD"]), "shared")
shared_directory = File.directory?(shared_directory) ? shared_directory : ENV["PWD"]

worker_processes Etc.nprocessors
timeout          30
preload_app      true
user             "app"

pid    File.join(shared_directory, "tmp", "unicorn.pid")
listen File.join(shared_directory, "tmp", "unicorn.sock")

logger Logger.new($stdout)

before_fork do |server, worker|
  defined?(ActiveRecord::Base) && ActiveRecord::Base.connection.disconnect!
  old_pid = "#{server.config[:pid]}.oldbin"
  if old_pid != server.pid
    begin
      sig = (worker.nr + 1) >= server.worker_processes ? :QUIT : :TTOU
      Process.kill(sig, File.read(old_pid).to_i)
    rescue Errno::ENOENT, Errno::ESRCH
    end
  end
end

after_fork do |server, worker|
  defined?(ActiveRecord::Base) && ActiveRecord::Base.establish_connection
end

before_exec do |server|
  ENV.update Dotenv.load
end
