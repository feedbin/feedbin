namespace :deploy do
  desc "Pause Sidekiq"
  task :quiet do
    on roles :app do
      execute :sudo, :pkill, "--signal USR1 -f '^sidekiq'"
    rescue SSHKit::Command::Failed
      puts "No workers running"
    end
  end
end
