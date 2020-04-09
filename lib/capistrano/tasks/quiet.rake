namespace :deploy do
  desc "Pause Sidekiq"
  task :quiet do
    on roles :app do
      execute :sudo, :systemctl, :reload, "feedbin.target"
    rescue SSHKit::Command::Failed
      puts "No workers running"
    end
  end
end
