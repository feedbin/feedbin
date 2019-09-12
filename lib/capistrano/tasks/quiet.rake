namespace :deploy do
  desc "Pause Sidekiq"
  task :quiet do
    on roles :app do
      execute :sudo, :quiet_sidekiq
    rescue SSHKit::Command::Failed
      puts "No workers running"
    end
  end
end
